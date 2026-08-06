let
  pkgs = import <nixpkgs> {};
  
  # Package local sgposit module
  sgposit = pkgs.python313Packages.buildPythonPackage {
    pname = "sgposit";
    version = "0.1.0";
    pyproject = true;
    buildInputs = [pkgs.python313Packages.setuptools];
    #build-system = [ "setuptools" ];
    src = pkgs.fetchFromGitHub {
      owner = "xman";
      repo = "sgpositpy";
      rev = "d538b54cb109a4a6f58a4a53188599a17faec701";
      hash = "sha256-cyzj16M8omGPZ+l/3iORZcIanuYr7rSLeImXrSziqxE=";
    };
  };
  softposit = pkgs.python313Packages.buildPythonPackage rec {
    pname = "softposit";
    version = "0.1.0";
    pyproject = true;

    src = pkgs.fetchgit {
      url = "https://gitlab.com/cerlane/SoftPosit-Python.git";
      rev = "c9498b37800551eead18539ecb018df0463d98e5";
      hash = "sha256-vPfa9wtM5ggFSYLtf1w2r52wa6PqnV4IwROW3W4Ajzw=";
    };

    sourceRoot = "${src.name}/softposit";

    # Delete the repository's stale build directories and pre-compiled wheels
    preBuild = ''
      rm -rf dist build *.egg-info
    '';

    nativeBuildInputs = [
      pkgs.python313Packages.setuptools
      pkgs.python313Packages.wheel
    ];
  };

  customPython = pkgs.python313.withPackages (ps: [
    ps.cocotb
    sgposit
    softposit
  ]);
in
pkgs.mkShell {
  packages = [
    customPython
    pkgs.ghdl
  ];
}
