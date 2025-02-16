{
  description = "ethereum.nix / A reproducible Nix package set for Ethereum clients and utilities";

  nixConfig = {
    extra-substituters = ["https://nix-community.cachix.org"];
    extra-trusted-public-keys = ["nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="];
  };

  inputs = {
    # packages
    nixpkgs.url = "github:nixos/nixpkgs/23.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    mynixpkgs = {
      url = "github:aldoborrero/mynixpkgs";
      inputs.devshell.follows = "devshell";
      inputs.flake-parts.follows = "flake-parts";
      inputs.flake-root.follows = "flake-root";
      inputs.lib-extras.follows = "lib-extras";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    foundry-nix = {
      url = "github:shazow/foundry.nix/monthly";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # flake-parts
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    flake-root.url = "github:srid/flake-root";

    # utils
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-compat.url = "github:nix-community/flake-compat";
    devour-flake = {
      url = "github:srid/devour-flake";
      flake = false;
    };
    lib-extras = {
      url = "github:aldoborrero/lib-extras/v0.2.2";
      inputs.devshell.follows = "devshell";
      inputs.flake-parts.follows = "flake-parts";
      inputs.flake-root.follows = "flake-root";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
  };

  outputs = inputs @ {
    flake-parts,
    nixpkgs,
    lib-extras,
    ...
  }: let
    lib = nixpkgs.lib.extend (l: _: {
      extras = (lib-extras.lib l) // (import ./lib.nix l);
    });
  in
    flake-parts.lib.mkFlake {
      inherit inputs;
      specialArgs = {inherit lib;};
    }
    {
      imports = [
        inputs.devshell.flakeModule
        inputs.flake-parts.flakeModules.easyOverlay
        inputs.flake-root.flakeModule
        inputs.treefmt-nix.flakeModule
        ./mkdocs.nix
        ./modules
        ./packages
      ];
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      perSystem = {
        config,
        pkgs,
        pkgsUnstable,
        system,
        ...
      }: {
        # pkgs
        _module.args = {
          pkgs = lib.extras.nix.mkNixpkgs {
            inherit system;
            inherit (inputs) nixpkgs;
          };
          pkgsUnstable = lib.extras.nix.mkNixpkgs {
            inherit system;
            nixpkgs = inputs.nixpkgs-unstable;
          };
        };

        # devshell
        devshells.default = {
          name = "ethereum.nix";
          packages = with pkgsUnstable; [
            nix-update
          ];
          commands = [
            {
              category = "Tools";
              name = "fmt";
              help = "Format the source tree";
              command = "nix fmt";
            }
            {
              category = "Tools";
              name = "check";
              help = "Checks the source tree";
              command = "nix flake check";
            }
          ];
        };

        # formatter
        treefmt.config = {
          inherit (config.flake-root) projectRootFile;
          flakeFormatter = true;
          flakeCheck = true;
          programs = {
            alejandra.enable = true;
            deadnix.enable = true;
            deno.enable = false;
            mdformat.enable = true;
            statix.enable = true;
          };
          settings.formatter = {
            # TODO: Re-enable deno whenever works again on x86_64-darwin
            # deno.command = lib.mkDefault pkgs.deno; # current deno from unstable don't work on darwin x86
            # deno.excludes = [
            #   "*.md"
            #   "*.html"
            # ];
            mdformat.command = lib.mkDefault (with pkgsUnstable.python3Packages;
              mdformat.withPlugins [
                mdformat-admon
                mdformat-beautysh
                mdformat-footnote
                mdformat-frontmatter
                mdformat-gfm
                mdformat-mkdocs
                mdformat-nix-alejandra
                mdformat-simple-breaks
                mdformat-toc
              ]);
            mdformat.excludes = [
              # mdformat doesn't behave well with some admonitions features
              "apps.md"
              "getting-started.md"
              "index.md"
              "restore-from-backup.md"
            ];
          };
        };

        # checks
        checks = let
          devour-flake = pkgs.callPackage inputs.devour-flake {};
        in
          {
            nix-build-all = pkgs.writeShellApplication {
              name = "nix-build-all";
              runtimeInputs = [
                pkgs.nix
                devour-flake
              ];
              text = ''
                # Make sure that flake.lock is sync
                nix flake lock --no-update-lock-file

                # Do a full nix build (all outputs)
                devour-flake . "$@"
              '';
            };
          }
          # mix in tests
          // config.testing.checks;
      };
    };
}
