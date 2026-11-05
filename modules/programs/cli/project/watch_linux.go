//go:build linux

package main

import "syscall"

// newDirWatcher watches one directory for churn among its entries: git
// writes its metadata through a lock file and a rename, and inotify reports
// that as create, move, and modify events of the directory itself. An
// in-place write of a file inside the directory reports too, so the mask
// keeps the modify flags. The watch ends with the directory, which a live
// worktree never removes. A pipe read end sits in the same select, so Close
// wakes the blocked read from another thread; close alone does not reliably
// end a blocked read on Linux.
func newDirWatcher(dir string) (*dirWatcher, error) {
	fd, err := syscall.InotifyInit1(syscall.IN_CLOEXEC)
	if err != nil {
		return nil, err
	}
	const mask = syscall.IN_CREATE | syscall.IN_DELETE | syscall.IN_MOVED_FROM |
		syscall.IN_MOVED_TO | syscall.IN_MODIFY | syscall.IN_ATTRIB | syscall.IN_CLOSE_WRITE
	if _, err := syscall.InotifyAddWatch(fd, dir, mask); err != nil {
		_ = syscall.Close(fd)
		return nil, err
	}
	var pipes [2]int
	if err := syscall.Pipe(pipes[:]); err != nil {
		_ = syscall.Close(fd)
		return nil, err
	}
	pipeRead, pipeWrite := pipes[0], pipes[1]
	w := &dirWatcher{events: make(chan struct{})}
	done := make(chan struct{})
	shut := make(chan struct{})
	go func() {
		defer close(done)
		defer close(w.events)
		buf := make([]byte, 4096)
		for {
			set := fdSet(fd, pipeRead)
			top := fd
			if pipeRead > top {
				top = pipeRead
			}
			n, err := syscall.Select(top+1, set, nil, nil, nil)
			if n <= 0 || err != nil {
				return
			}
			if fdReady(set, pipeRead) {
				return
			}
			if _, err := syscall.Read(fd, buf); err != nil {
				return
			}
			select {
			case w.events <- struct{}{}:
			case <-shut:
				return
			}
		}
	}()
	w.close = func() {
		// shut releases a send that no loop reads any more, and the byte
		// wakes the goroutine out of select; it then owns the end of the
		// channel, so the fds close only after it is out
		close(shut)
		_, _ = syscall.Write(pipeWrite, []byte("x"))
		<-done
		_ = syscall.Close(pipeWrite)
		_ = syscall.Close(fd)
	}
	return w, nil
}

// fdSet builds the read set of one select call over the given descriptors.
func fdSet(fds ...int) *syscall.FdSet {
	set := &syscall.FdSet{}
	for _, fd := range fds {
		set.Bits[fd/64] |= 1 << (uint(fd) % 64)
	}
	return set
}

// fdReady reports whether select marked the descriptor ready.
func fdReady(set *syscall.FdSet, fd int) bool {
	return set.Bits[fd/64]&(1<<(uint(fd)%64)) != 0
}
