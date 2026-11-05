//go:build darwin

package main

import "syscall"

// newDirWatcher watches one directory for churn among its entries: git
// writes its metadata through a lock file and a rename, and a vnode watch on
// the directory reports that. An in-place write of a file inside the
// directory would not report, and no git command writes that directory in
// place. The watch ends with the directory, which a live worktree never
// removes. A pipe read end sits in the same queue, so Close wakes the
// blocking kevent from another thread; closing a kqueue fd under a blocked
// kevent has no defined result on Darwin.
func newDirWatcher(dir string) (*dirWatcher, error) {
	fd, err := syscall.Open(dir, syscall.O_EVTONLY, 0)
	if err != nil {
		return nil, err
	}
	kq, err := syscall.Kqueue()
	if err != nil {
		_ = syscall.Close(fd)
		return nil, err
	}
	var pipes [2]int
	if err := syscall.Pipe(pipes[:]); err != nil {
		_ = syscall.Close(kq)
		_ = syscall.Close(fd)
		return nil, err
	}
	pipeRead, pipeWrite := pipes[0], pipes[1]
	changes := []syscall.Kevent_t{
		{
			Ident:  uint64(fd),
			Filter: syscall.EVFILT_VNODE,
			Flags:  syscall.EV_ADD | syscall.EV_ENABLE,
			Fflags: syscall.NOTE_WRITE | syscall.NOTE_DELETE | syscall.NOTE_RENAME | syscall.NOTE_EXTEND | syscall.NOTE_ATTRIB,
		},
		{
			Ident:  uint64(pipeRead),
			Filter: syscall.EVFILT_READ,
			Flags:  syscall.EV_ADD | syscall.EV_ENABLE,
		},
	}
	if _, err := syscall.Kevent(kq, changes, nil, nil); err != nil {
		_ = syscall.Close(pipeWrite)
		_ = syscall.Close(pipeRead)
		_ = syscall.Close(kq)
		_ = syscall.Close(fd)
		return nil, err
	}
	w := &dirWatcher{events: make(chan struct{})}
	done := make(chan struct{})
	shut := make(chan struct{})
	go func() {
		defer close(done)
		defer close(w.events)
		kevents := make([]syscall.Kevent_t, 8)
		for {
			n, err := syscall.Kevent(kq, nil, kevents, nil)
			if n <= 0 || err != nil {
				return
			}
			for i := range n {
				if kevents[i].Ident == uint64(pipeRead) {
					return
				}
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
		// wakes the goroutine out of kevent; it then owns the end of the
		// channel, so the fds close only after it is out
		close(shut)
		_, _ = syscall.Write(pipeWrite, []byte("x"))
		<-done
		_ = syscall.Close(pipeWrite)
		_ = syscall.Close(kq)
		_ = syscall.Close(fd)
	}
	return w, nil
}
