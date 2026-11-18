#!/bin/bash
SESSION="server-monitor"

tmux new-session -d -s $SESSION

# Pane 0 (Top-Left): Arc B580 VRAM & Core Stats via Fedora-hosted nvtop
tmux rename-window -t $SESSION:0 "Server-Overview"
tmux send-keys -t $SESSION:0.0 "distrobox enter monbox -- nvtop" C-m

# Pane 1 (Top-Right): CPU, RAM, Disk, and Network via btop
tmux split-window -h -t $SESSION:0
tmux send-keys -t $SESSION:0.1 "distrobox enter monbox -- btop" C-m

# Pane 2 (Bottom-Left): Live K3s Pod Resource Footprint (CPU/RAM)
tmux split-window -v -t $SESSION:0.0
tmux send-keys -t $SESSION:0.2 "watch -n 2 'kubectl top pods -n ai-workloads'" C-m

# Pane 3 (Bottom-Right): Live Ollama Token Generation Logs
tmux split-window -v -t $SESSION:0.1
tmux send-keys -t $SESSION:0.3 "kubectl logs -f ollama-intel-0 -n ai-workloads --tail=50" C-m

tmux attach-session -t $SESSION
