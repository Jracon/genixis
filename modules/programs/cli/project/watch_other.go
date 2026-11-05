//go:build !darwin && !linux

package main

import (
	"fmt"
	"runtime"
)

// newDirWatcher has no implementation on this platform: the tool builds for
// Darwin and Linux, and another platform gets no watchdog, so the yazi pane
// keeps the behaviour it had before issue #128.
func newDirWatcher(dir string) (*dirWatcher, error) {
	return nil, fmt.Errorf("no directory watcher on %s", runtime.GOOS)
}
