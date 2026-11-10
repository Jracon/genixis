# Compressed swap in RAM (issue 267): the host has no disk swap, so under
# memory pressure the kernel could only reclaim page cache, and every
# executable page faulted in from disk, was evicted, and faulted again. With
# zram, cold anonymous pages compress into RAM instead, pressure degrades,
# and the kill at the MemoryMax cap of the user slice stays a late and clean
# event (user-slice-memory.nix).
#
# memoryPercent 50 gives an 8 GB device on the 16 GB of the host.
{
  zramSwap = {
    enable = true;

    memoryPercent = 50;
  };
}
