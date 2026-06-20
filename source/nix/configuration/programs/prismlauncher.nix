{
  pkgs,
  ...
}:

{
  programs.prismlauncher = {
    enable = true;
    package = (
      pkgs.prismlauncher.override {
        jdks = with pkgs.javaPackages.compiler.temurin-bin; [
          jre-8
          jre-17
          jre-21
          jre-25
        ];
      }
    );
  };
}
