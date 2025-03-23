{
  ...
}:

{
  networking.firewall = {
    allowedTCPPorts = [
      8010
    ];
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
    }
  };
}
