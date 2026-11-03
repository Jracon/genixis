//go:build linux

package main

import (
	"os"
	"syscall"
	"unsafe"
)

// isTerminal reports whether f is a terminal, the check that gates discard.
// It asks the tty directly, because os.Stat cannot tell a character device
// that is a terminal from one that is not (/dev/null is both a character
// device and no terminal).
func isTerminal(f *os.File) bool {
	var termios [8]int64
	_, _, errno := syscall.Syscall6(syscall.SYS_IOCTL, f.Fd(), syscall.TCGETS,
		uintptr(unsafe.Pointer(&termios[0])), 0, 0, 0)
	return errno == 0
}
