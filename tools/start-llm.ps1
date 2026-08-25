# Launch llama-server for Maldari.
# Edit the paths below to match your machine.

$server = 'C:\Users\senso\llama.cpp\llama-server.exe'
$model  = 'C:\Users\senso\Models\gemma-4-E4B-it\gemma-4-E4B-it-Q4_K_M.gguf'

& $server `
    -m $model `
    --host 127.0.0.1 `
    --port 8080 `
    -c 2048 `
    -ngl 99 `
    -fit off `
    --jinja `
    --alias maldari-gemma
