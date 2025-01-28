{
    config, 
    ...
}:

{
    boot = {
        isContainer = true;
        postBootCommands = ''
            # After booting, register the contents of the Nix store in the Nix
            # database.
            if [ -f /nix-path-registration ]; then
            ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration &&
            rm /nix-path-registration
            fi

            # nixos-rebuild also requires a "system" profile
            ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
        '';
    };

    # proxmox-exclusive
    systemd = {
        mounts = mkIf (!cfg.privileged) [
          {
            enable = false;
            where = "/sys/kernel/debug";
          }
        ];

        # By default only starts getty on tty0 but first on LXC is tty1
        services."autovt@".unitConfig.ConditionPathExists = [
          ""
          "/dev/%I"
        ];

        # These are disabled by `console.enable` but console via tty is the default in Proxmox
        services."getty@tty1".enable = lib.mkForce true;
        services."autovt@".enable = lib.mkForce true;
    };
}