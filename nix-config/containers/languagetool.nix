{ 
  pkgs, 
  ...
}:

{
  # environment.systemPackages = [
  #   pkgs.unzip
  # ];

  networking.firewall = {
    allowedTCPPorts = [
      8010
    ];
  };

  system.activationScripts = {
    download_languagetool_ngrams.text = ''
      test -d /mnt/languagetool/ngrams/data || mkdir -p /mnt/languagetool/ngrams/data && ${pkgs.curl}/bin/curl --output /mnt/languagetool/ngrams/data/ngrams.zip "https://languagetool.org/download/ngram-data/ngrams-en-20150817.zip" && ${pkgs.unzip}/bin/unzip /mnt/languagetool/ngrams/data/ngrams.zip && rm /mnt/languagetool/ngrams/data/ngrams.zip
    '';
  };

  virtualisation.oci-containers.containers = {
    languagetool = {
      hostname = "languagetool";
      image = "erikvl87/languagetool";

      environment = {
        langtool_languageModel = "/ngrams";
        Java_Xms = "512m";
        Java_Xmx = "1g";
      };
      ports = [
        "8010:8010"
      ];
      pull = "always";
      volumes = [
        "/mnt/languagetool/ngrams/data:/ngrams"
      ];
    };
  };
}
