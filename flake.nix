{
  inputs.comfyui.url = "github:BatteredBunny/nix-ai-stuff";
  inputs.nixpkgs.follows = "comfyui/nixpkgs";

  outputs = { self, comfyui, nixpkgs }: {

    configurablePackages.x86_64-linux.default =

      with import nixpkgs { system = "x86_64-linux"; };

      {
        options = {
          port = {
            type = lib.types.int;
            default = 8080;
            description = "Port on which to listen.";
          };

          useCPU = {
            type = lib.types.bool;
            default = false;
            description = "Use the CPU rather than the GPU.";
          };

          checkpoints = {
            type = lib.types.listOf lib.types.package;
            default = [];
            description = "List of checkpoint packages.";
          };

          loras = {
            type = lib.types.listOf lib.types.package;
            default = [];
            description = "List of LORA packages.";
          };
        };

        applyOptions = options:
          let
            checkpoints = runCommand "comfyui-checkpoints"
              {
                checkpoints = options.checkpoints;
              }
              ''
                mkdir $out
                for checkpoint in $checkpoints; do
                  ln -sfn "$checkpoint" "$out/$(basename "$checkpoint" | cut -c34-)"
                done
              '';
            loras = runCommand "comfyui-loras"
              {
                loras = options.loras;
              }
              ''
                mkdir $out
                for lora in $loras; do
                  ln -sfn "$lora" "$out/$(basename "$lora" | cut -c34-)"
                done
              '';
            extra_model_paths = pkgs.writeText "extra_model_paths.yaml"
              ''
                comfyui:
                  checkpoints: ${checkpoints}
                  loras: ${loras}
              '';
          in
          runCommand "comfyui-wrapper"
            {
              buildInputs = [ makeWrapper ];
              meta.mainProgram = "comfyui";
            }
            ''
              mkdir -p $out/bin
              cat > $out/bin/comfyui <<EOF
              #! $shell -e
              datadir="\$HOME/.local/state/comfyui"
              mkdir -p "\$datadir" "\$datadir/custom_nodes"
              cd "\$datadir"
              exec ${comfyui.packages.x86_64-linux.comfyui}/bin/comfyui \
                --port ${toString options.port} \
                --extra-model-paths-config ${extra_model_paths} \
                --output-directory "\$HOME/ComfyUI" \
                ${if options.useCPU then "--cpu" else ""} \
                "\$@"
              EOF
              chmod +x $out/bin/comfyui
            '';
      };

    checkpoints.stable-diffusion-v1-5-pruned-emaonly = import <nix/fetchurl.nix> {
      url = https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors;
      sha256 = "6ce0161689b3853acaa03779ec93eafe75a02f4ced659bee03f50797806fa2fa";
    };

    loras.AlanLeeV1_1 = import <nix/fetchurl.nix> {
      name = "AlanLeeV1_1.safetensors";
      url = "https://civitai.com/api/download/models/137927?type=Model&format=SafeTensor";
      hash = "sha256-sKTmQq4b5fWjnAAzvDYyx8tpIPFcJhJyF98LHFvwqlo=";
    };

    packages.x86_64-linux.test =
      self.configurablePackages.x86_64-linux.default.applyOptions {
        port = 2080;
        checkpoints = [ self.checkpoints.stable-diffusion-v1-5-pruned-emaonly ];
        loras = [ self.loras.AlanLeeV1_1 ];
      };
  };
}
