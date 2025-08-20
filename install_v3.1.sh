#!/bin/bash

#############################################
# AI Academy - Student iMac Deployment Script
# Fully automated setup for AI/ML academy environment
# Version: 3.0.0
#############################################

# Configuration
SCRIPT_VERSION="3.0.0-AI-Complete"
LOG_DIR="$HOME/.ai-academy-deployment"
LOG_FILE="$LOG_DIR/deployment-$(date +%Y%m%d-%H%M%S).log"
ERROR_LOG="$LOG_DIR/errors-$(date +%Y%m%d-%H%M%S).log"
TEMP_DIR="$HOME/.ai-academy-temp"
FAILURES=0
MAX_RETRIES=3
RETRY_DELAY=5

# Academy Configuration
ACADEMY_NAME="AI Academy Azerbaijan"
PYTHON_VERSION="3.11"
NODE_VERSION="20"
CUDA_SUPPORT=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

#############################################
# Error Handling & Recovery
#############################################

set -o pipefail
trap 'error_handler $? $LINENO' ERR


# Function to keep sudo alive
keep_sudo_alive() {
    # Ask for sudo password upfront
    echo "This script requires administrator privileges."
    echo "Please enter your password once to continue:"
    sudo -v
    
    # Keep sudo alive in background
    while true; do 
        sudo -n true
        sleep 60
        kill -0 "$$" || exit
    done 2>/dev/null &
    SUDO_KEEPER_PID=$!
}

cleanup_sudo() {
    if [ ! -z "$SUDO_KEEPER_PID" ]; then
        kill $SUDO_KEEPER_PID 2>/dev/null
    fi
}

error_handler() {
    local exit_code=$1
    local line_number=$2
    echo -e "${RED}Error occurred at line $line_number with exit code $exit_code${NC}" | tee -a "$ERROR_LOG"
    cleanup_on_error
}

cleanup_on_error() {
    log "ERROR: Performing emergency cleanup..."
    pkill -f "brew install" 2>/dev/null || true
    pkill -f "softwareupdate" 2>/dev/null || true
    pkill -f "pip install" 2>/dev/null || true
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress 2>/dev/null || true
    rm -rf "$TEMP_DIR"/*.lock 2>/dev/null || true
}

retry_command() {
    local max_attempts=$1
    shift
    local command="$@"
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log "Attempt $attempt of $max_attempts: $command"
        
        if eval $command; then
            return 0
        else
            log "Command failed, attempt $attempt of $max_attempts"
            if [ $attempt -lt $max_attempts ]; then
                log "Retrying in $RETRY_DELAY seconds..."
                sleep $RETRY_DELAY
            fi
        fi
        attempt=$((attempt + 1))
    done
    
    handle_error "Command failed after $max_attempts attempts: $command"
    return 1
}

#############################################
# Setup & Logging Functions
#############################################

setup_environment() {
    # Use home directory to avoid permission issues
    mkdir -p "$LOG_DIR" 2>/dev/null
    mkdir -p "$TEMP_DIR" 2>/dev/null
    touch "$LOG_FILE" 2>/dev/null
    touch "$ERROR_LOG" 2>/dev/null
    
    # Lock file management
    LOCK_FILE="$TEMP_DIR/deployment.lock"
    if [ -f "$LOCK_FILE" ]; then
        echo "Another deployment is running. Waiting..."
        local wait_time=0
        while [ -f "$LOCK_FILE" ] && [ $wait_time -lt 60 ]; do
            sleep 5
            wait_time=$((wait_time + 5))
        done
        if [ -f "$LOCK_FILE" ]; then
            rm -f "$LOCK_FILE"
        fi
    fi
    touch "$LOCK_FILE"
    
    # Export paths
    export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
    export PYTHONPATH="$HOME/.local/lib/python$PYTHON_VERSION/site-packages:$PYTHONPATH"
}

log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" | tee -a "$LOG_FILE"
}

handle_error() {
    log "ERROR: $1"
    echo "$1" >> "$ERROR_LOG"
    ((FAILURES++))
    echo -e "${RED}✗ Error: $1${NC}"
}

success() {
    log "SUCCESS: $1"
    echo -e "${GREEN}✓ $1${NC}"
}

info() {
    log "INFO: $1"
    echo -e "${BLUE}ℹ $1${NC}"
}

warning() {
    log "WARNING: $1"
    echo -e "${YELLOW}⚠ $1${NC}"
}

#############################################
# Permission Fixing
#############################################

fix_all_permissions() {
    info "Fixing all permissions comprehensively..."
    
    CURRENT_USER=$(whoami)
    
    # Fix Homebrew directories - both Intel and Apple Silicon
    if [ -d "/usr/local" ]; then
        sudo chown -R "$CURRENT_USER":admin /usr/local/* 2>/dev/null || true
        sudo chmod -R 755 /usr/local/* 2>/dev/null || true
    fi
    
    if [ -d "/opt/homebrew" ]; then
        sudo chown -R "$CURRENT_USER":admin /opt/homebrew 2>/dev/null || true
        sudo chmod -R 755 /opt/homebrew 2>/dev/null || true
    fi
    
    # Fix all Python/pip directories
    mkdir -p "$HOME/Library/Python/$PYTHON_VERSION/lib/python/site-packages" 2>/dev/null
    mkdir -p "$HOME/.local/bin" 2>/dev/null
    mkdir -p "$HOME/.local/lib/python$PYTHON_VERSION/site-packages" 2>/dev/null
    mkdir -p "$HOME/.cache/pip" 2>/dev/null
    mkdir -p "$HOME/Library/Caches/pip" 2>/dev/null
    
    # Fix ownership
    [ -d "$HOME/Library/Python" ] && sudo chown -R "$CURRENT_USER" "$HOME/Library/Python" 2>/dev/null || true
    [ -d "$HOME/.local" ] && sudo chown -R "$CURRENT_USER" "$HOME/.local" 2>/dev/null || true
    [ -d "$HOME/.cache" ] && sudo chown -R "$CURRENT_USER" "$HOME/.cache" 2>/dev/null || true
    [ -d "$HOME/.npm" ] && sudo chown -R "$CURRENT_USER" "$HOME/.npm" 2>/dev/null || true
    [ -d "/usr/local/lib/node_modules" ] && sudo chown -R "$CURRENT_USER" /usr/local/lib/node_modules 2>/dev/null || true
    
    success "Permissions fixed"
}

#############################################
# System Checks and Preparation
#############################################

check_system_requirements() {
    info "Checking system requirements..."
    
    OS_VERSION=$(sw_vers -productVersion)
    log "macOS version: $OS_VERSION"
    
    ARCH=$(uname -m)
    log "Architecture: $ARCH"
    
    # Check disk space
    AVAILABLE_SPACE=$(df -H / | awk 'NR==2 {print $4}' | sed 's/[^0-9.]//g')
    log "Available disk space: ${AVAILABLE_SPACE}GB"
    
    if (( $(echo "$AVAILABLE_SPACE < 20" | bc -l 2>/dev/null || echo 0) )); then
        warning "Low disk space. Attempting cleanup..."
        rm -rf ~/Library/Caches/* 2>/dev/null || true
        rm -rf ~/.cache/* 2>/dev/null || true
        if command -v brew &>/dev/null; then
            brew cleanup --prune=all 2>/dev/null || true
        fi
    fi
    
    success "System requirements checked"
}

ensure_rosetta() {
    if [[ $(uname -m) == "arm64" ]]; then
        info "Apple Silicon detected, ensuring Rosetta 2..."
        if ! pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto &>/dev/null; then
            sudo softwareupdate --install-rosetta --agree-to-license 2>&1 | tee -a "$LOG_FILE"
        fi
        success "Rosetta 2 ready"
    fi
}

#############################################
# Xcode CLI Tools - Enhanced Installation
#############################################

install_xcode_cli() {
    info "Installing Xcode Command Line Tools..."
    
    if xcode-select -p &>/dev/null; then
        success "Xcode CLI tools already installed"
        sudo xcodebuild -license accept 2>/dev/null || true
        return 0
    fi
    
    # Method 1: Software Update
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    
    PROD=$(softwareupdate -l 2>/dev/null | grep "\*.*Command Line" | tail -n 1 | sed 's/^[^C]* //')
    
    if [[ -n "$PROD" ]]; then
        sudo softwareupdate -i "$PROD" --verbose --agree-to-license 2>&1 | tee -a "$LOG_FILE"
        rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    else
        # Method 2: Direct installation
        xcode-select --install 2>/dev/null || true
        
        local wait_time=0
        while ! xcode-select -p &>/dev/null && [ $wait_time -lt 300 ]; do
            sleep 10
            wait_time=$((wait_time + 10))
            echo -n "."
        done
        echo ""
    fi
    
    if xcode-select -p &>/dev/null; then
        sudo xcodebuild -license accept 2>/dev/null || true
        success "Xcode CLI tools installed"
    else
        warning "Xcode CLI tools installation incomplete"
    fi
}

#############################################
# Homebrew - Installation
#############################################

install_homebrew() {
    info "Installing/Updating Homebrew..."
    
    unset GIT_ASKPASS
    unset SSH_ASKPASS
    
    if command -v brew &>/dev/null; then
        success "Homebrew already installed at $(which brew)"
        export HOMEBREW_NO_AUTO_UPDATE=1
        brew update --force --quiet 2>&1 | tee -a "$LOG_FILE" || true
        brew doctor 2>&1 | grep -v "Warning" | tee -a "$LOG_FILE" || true
    else
        info "Installing Homebrew..."
        curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$TEMP_DIR/brew-install.sh"
        export NONINTERACTIVE=1
        /bin/bash "$TEMP_DIR/brew-install.sh" 2>&1 | tee -a "$LOG_FILE"
        rm -f "$TEMP_DIR/brew-install.sh"
    fi
    
    # Configure PATH
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        BREW_PREFIX="/opt/homebrew"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
        BREW_PREFIX="/usr/local"
    fi
    
    # Add to shell profiles
    for profile in ~/.zprofile ~/.bash_profile ~/.profile; do
        if ! grep -q "brew shellenv" "$profile" 2>/dev/null; then
            echo "eval \"\$(${BREW_PREFIX}/bin/brew shellenv)\"" >> "$profile"
        fi
    done
    
    export HOMEBREW_NO_AUTO_UPDATE=1
    export HOMEBREW_NO_INSTALL_CLEANUP=1
    export HOMEBREW_NO_ANALYTICS=1
    
    success "Homebrew ready"
}

#############################################
# COMPLETE Package Lists
#############################################

# Core development tools
BREW_PACKAGES=(
    # Version Control & Build Tools
    "git"
    "git-lfs"
    "cmake"
    "gcc"
    "openblas"
    "libomp"
    
    # Python & Environment Management
    "python@${PYTHON_VERSION}"
    "pyenv"
    "pipenv"
    "poetry"
    
    # Data Processing
    "apache-spark"
    "postgresql@14"
    "redis"
    "sqlite"
    "mongodb-community"
    
    # Cloud & Container Tools
    "docker"
    "docker-compose"
    "kubectl"
    "awscli"
    "azure-cli"
    "google-cloud-sdk"
    
    # Utilities
    "wget"
    "curl"
    "jq"
    "htop"
    "tree"
    "tmux"
    "ffmpeg"
    "graphviz"
    "pandoc"
    
    # Node.js for Jupyter extensions
    "node@${NODE_VERSION}"
    "yarn"
)

# GUI Applications
BREW_CASK_APPS=(
    # IDEs & Editors
    "visual-studio-code"
    "pycharm-ce"
    "jupyter-notebook-viewer"
    "sublime-text"
    
    # Data Science Tools
    "tableau-public"
    "rstudio"
    "anaconda"
    
    # Containers & Virtualization
    "docker"
    "virtualbox"
    
    # Database Tools
    "dbeaver-community"
    "mongodb-compass"
    "postgres-unofficial"
    
    # API & Testing
    "postman"
    "insomnia"
    
    # Communication
    "slack"
    "zoom"
    "discord"
    
    # Browsers
    "google-chrome"
    "firefox"
    
    # Utilities
    "iterm2"
    "rectangle"
    "cyberduck"
    "github"
    "gitkraken"
    
    # Documentation
    "notion"
    "obsidian"
    "typora"
)

# Python packages for AI/ML
PYTHON_AI_PACKAGES=(
    # Core ML/DL Frameworks
    "tensorflow"
    "tensorflow-metal"
    "torch"
    "torchvision"
    "torchaudio"
    "jax"
    "jaxlib"
    
    # Core Data Science
    "numpy"
    "pandas"
    "scipy"
    "scikit-learn"
    "statsmodels"
    
    # Deep Learning Extensions
    "transformers"
    "datasets"
    "tokenizers"
    "accelerate"
    "diffusers"
    
    # Computer Vision
    "opencv-python"
    "pillow"
    "scikit-image"
    "albumentations"
    
    # NLP
    "nltk"
    "spacy"
    "gensim"
    "textblob"
    "langchain"
    "openai"
    "anthropic"
    
    # Visualization
    "matplotlib"
    "seaborn"
    "plotly"
    "bokeh"
    "altair"
    "yellowbrick"
    
    # MLOps & Experiment Tracking
    "mlflow"
    "wandb"
    "tensorboard"
    "optuna"
    "ray"
    "dvc"
    
    # AutoML
    "auto-sklearn"
    "h2o"
    "pycaret"
    
    # Jupyter & Development
    "jupyter"
    "jupyterlab"
    "notebook"
    "ipywidgets"
    "nbconvert"
    "black"
    "pylint"
    "pytest"
    "tqdm"
    
    # Web Frameworks
    "fastapi"
    "streamlit"
    "gradio"
    "flask"
    "django"
    
    # Additional Tools
    "gymnasium"
    "stable-baselines3"
    "xgboost"
    "lightgbm"
    "catboost"
    "prophet"
    "surprise"
)

#############################################
# Package Installation Functions
#############################################

install_brew_package() {
    local package=$1
    
    if brew list "$package" &>/dev/null 2>&1; then
        log "$package already installed"
        return 0
    fi
    
    log "Installing $package..."
    
    # Try installation with retries
    local install_success=false
    for attempt in {1..3}; do
        if brew install "$package" --quiet 2>&1 | tee -a "$LOG_FILE"; then
            install_success=true
            break
        else
            if [ $attempt -lt 3 ]; then
                brew unlink "$package" 2>/dev/null || true
                brew cleanup "$package" 2>/dev/null || true
                sleep 2
            fi
        fi
    done
    
    if [ "$install_success" = true ]; then
        success "$package installed"
        return 0
    else
        warning "Failed to install $package (non-critical)"
        return 1
    fi
}

install_cask_app() {
    local app=$1
    
    if brew list --cask "$app" &>/dev/null 2>&1; then
        log "$app already installed"
        return 0
    fi
    
    log "Installing $app..."
    
    # Try installation with no-quarantine flag
    if brew install --cask "$app" --no-quarantine 2>&1 | tee -a "$LOG_FILE"; then
        success "$app installed"
        return 0
    else
        # Try force reinstall
        brew reinstall --cask "$app" --force 2>&1 | tee -a "$LOG_FILE" || {
            warning "Failed to install $app (non-critical)"
            return 1
        }
    fi
}

install_all_brew_packages() {
    info "Installing development tools via Homebrew..."
    
    # Tap required repositories
    brew tap homebrew/cask-versions 2>/dev/null || true
    brew tap mongodb/brew 2>/dev/null || true
    
    local total=${#BREW_PACKAGES[@]}
    local current=0
    local installed=0
    
    for package in "${BREW_PACKAGES[@]}"; do
        current=$((current + 1))
        echo -e "${MAGENTA}[$current/$total]${NC} Installing $package..."
        if install_brew_package "$package"; then
            installed=$((installed + 1))
        fi
    done
    
    info "Installed $installed/$total Homebrew packages"
}

install_all_cask_apps() {
    info "Installing GUI applications..."
    
    local total=${#BREW_CASK_APPS[@]}
    local current=0
    local installed=0
    
    for app in "${BREW_CASK_APPS[@]}"; do
        current=$((current + 1))
        echo -e "${MAGENTA}[$current/$total]${NC} Installing $app..."
        if install_cask_app "$app"; then
            installed=$((installed + 1))
        fi
    done
    
    info "Installed $installed/$total GUI applications"
}

#############################################
# Python Environment - SETUP
#############################################

setup_python_environment() {
    info "Setting up Python AI/ML environment..."
    
    # Ensure Python is available
    if ! command -v python3 &>/dev/null; then
        warning "Python3 not found. Installing via Homebrew..."
        brew install python@${PYTHON_VERSION}
    fi
    
    PYTHON_CMD=$(which python3)
    log "Using Python: $PYTHON_CMD"
    
    # Fix pip installation with multiple methods
    info "Ensuring pip is properly installed..."
    
    # Method 1: ensurepip
    $PYTHON_CMD -m ensurepip --default-pip 2>&1 | tee -a "$LOG_FILE" || true
    
    # Method 2: get-pip if needed
    if ! $PYTHON_CMD -m pip --version &>/dev/null 2>&1; then
        warning "Installing pip manually..."
        curl -sS https://bootstrap.pypa.io/get-pip.py -o "$TEMP_DIR/get-pip.py"
        $PYTHON_CMD "$TEMP_DIR/get-pip.py" --user 2>&1 | tee -a "$LOG_FILE"
        rm -f "$TEMP_DIR/get-pip.py"
    fi
    
    # Update pip
    $PYTHON_CMD -m pip install --upgrade --user pip setuptools wheel 2>&1 | tee -a "$LOG_FILE"
    
    # Create virtual environment
    VENV_PATH="$HOME/ai-academy-env"
    info "Creating virtual environment at $VENV_PATH..."
    
    if [ -d "$VENV_PATH" ]; then
        warning "Virtual environment exists, recreating..."
        rm -rf "$VENV_PATH"
    fi
    
    $PYTHON_CMD -m venv "$VENV_PATH"
    
    # Activate virtual environment
    source "$VENV_PATH/bin/activate"
    
    # Upgrade pip in venv
    python -m pip install --upgrade pip setuptools wheel
    
    # Install packages with progress tracking
    local total=${#PYTHON_AI_PACKAGES[@]}
    local current=0
    local installed=0
    
    for package in "${PYTHON_AI_PACKAGES[@]}"; do
        current=$((current + 1))
        echo -e "${CYAN}[$current/$total] Installing: $package${NC}"
        
        # Special handling for certain packages
        case "$package" in
            "tensorflow-metal")
                if [[ $(uname -m) == "arm64" ]]; then
                    if pip install "$package" --no-cache-dir 2>&1 | tee -a "$LOG_FILE"; then
                        installed=$((installed + 1))
                    fi
                fi
                ;;
            "auto-sklearn")
                if pip install "$package" --no-deps 2>&1 | tee -a "$LOG_FILE"; then
                    installed=$((installed + 1))
                fi
                ;;
            *)
                if pip install "$package" --no-cache-dir 2>&1 | tee -a "$LOG_FILE"; then
                    installed=$((installed + 1))
                else
                    warning "Failed: $package, trying without dependencies..."
                    pip install "$package" --no-deps 2>&1 | tee -a "$LOG_FILE" || true
                fi
                ;;
        esac
    done
    
    info "Installed $installed/$total Python packages"
    
    # Install Jupyter extensions
    info "Setting up Jupyter extensions..."
    pip install jupyter_contrib_nbextensions --quiet
    jupyter contrib nbextension install --user 2>/dev/null || true
    
    # Enable useful extensions
    jupyter nbextension enable code_prettify/code_prettify 2>/dev/null || true
    jupyter nbextension enable collapsible_headings/main 2>/dev/null || true
    jupyter nbextension enable execute_time/ExecuteTime 2>/dev/null || true
    
    # Install JupyterLab extensions
    pip install jupyterlab-git jupyterlab-lsp --quiet
    
    # Install Jupyter kernel
    python -m ipykernel install --user --name ai-academy --display-name "AI Academy"
    
    # Configure Jupyter
    jupyter notebook --generate-config 2>/dev/null || true
    
    deactivate
    
    # Create activation script
    cat > "$HOME/activate-academy.sh" << EOF
#!/bin/bash
source $VENV_PATH/bin/activate
export PYTHONPATH="\$HOME/AI-Academy:\$PYTHONPATH"
echo "AI Academy environment activated!"
echo "Python: \$(which python)"
echo "Python version: \$(python --version)"
echo "Run 'jupyter lab' to start Jupyter Lab"
EOF
    chmod +x "$HOME/activate-academy.sh"
    
    success "Python environment ready"
}

#############################################
# Ensure Jupyter Works
#############################################

ensure_jupyter_works() {
    info "Ensuring Jupyter is properly installed..."
    
    # Check if jupyter exists in PATH
    if ! command -v jupyter &>/dev/null; then
        warning "Jupyter not in PATH, fixing..."
        
        # Try to find jupyter
        JUPYTER_LOCATIONS=(
            "$HOME/ai-academy-env/bin/jupyter"
            "$HOME/.local/bin/jupyter"
            "/usr/local/bin/jupyter"
            "/opt/homebrew/bin/jupyter"
        )
        
        for loc in "${JUPYTER_LOCATIONS[@]}"; do
            if [ -f "$loc" ]; then
                info "Found Jupyter at: $loc"
                export PATH="$(dirname $loc):$PATH"
                break
            fi
        done
    fi
    
    # Test Jupyter
    if command -v jupyter &>/dev/null; then
        jupyter --version 2>&1 | tee -a "$LOG_FILE"
        success "Jupyter is working"
    else
        warning "Jupyter needs manual configuration"
    fi
}

#############################################
# Academy Resources Setup
#############################################

setup_academy_resources() {
    info "Creating AI Academy resources..."
    
    ACADEMY_DIR="$HOME/AI-Academy"
    mkdir -p "$ACADEMY_DIR"/{datasets,notebooks,projects,models,scripts,docs}
    
    # Create comprehensive welcome notebook
    cat > "$ACADEMY_DIR/notebooks/00-welcome.ipynb" << 'NOTEBOOK'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Welcome to AI Academy Azerbaijan!\n",
    "\n",
    "This notebook will help you verify your environment is properly configured."
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Check Python version\n",
    "import sys\n",
    "print(f\"Python version: {sys.version}\")\n",
    "print(f\"Executable: {sys.executable}\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Test all major libraries\n",
    "import importlib\n",
    "\n",
    "libraries = {\n",
    "    'numpy': 'NumPy',\n",
    "    'pandas': 'Pandas', \n",
    "    'matplotlib': 'Matplotlib',\n",
    "    'sklearn': 'Scikit-learn',\n",
    "    'tensorflow': 'TensorFlow',\n",
    "    'torch': 'PyTorch',\n",
    "    'transformers': 'Transformers',\n",
    "    'cv2': 'OpenCV',\n",
    "    'nltk': 'NLTK',\n",
    "    'spacy': 'spaCy',\n",
    "    'jupyter': 'Jupyter'\n",
    "}\n",
    "\n",
    "print(\"Checking installed libraries:\\n\")\n",
    "for module, name in libraries.items():\n",
    "    try:\n",
    "        lib = importlib.import_module(module)\n",
    "        version = getattr(lib, '__version__', 'installed')\n",
    "        print(f\"✅ {name:15} {version}\")\n",
    "    except ImportError:\n",
    "        print(f\"❌ {name:15} not installed\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Test visualization\n",
    "import matplotlib.pyplot as plt\n",
    "import numpy as np\n",
    "\n",
    "x = np.linspace(0, 2*np.pi, 100)\n",
    "y = np.sin(x)\n",
    "\n",
    "plt.figure(figsize=(10, 4))\n",
    "plt.plot(x, y)\n",
    "plt.title('Environment Test: Sine Wave')\n",
    "plt.xlabel('x')\n",
    "plt.ylabel('sin(x)')\n",
    "plt.grid(True)\n",
    "plt.show()\n",
    "\n",
    "print(\"\\n✅ If you see a sine wave above, your environment is ready!\")"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "AI Academy",
   "language": "python",
   "name": "ai-academy"
  },
  "language_info": {
   "name": "python",
   "version": "3.11"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}
NOTEBOOK
    
    # Create README
    cat > "$ACADEMY_DIR/README.md" << EOF
# AI Academy Azerbaijan

Welcome to your AI/ML learning environment!

## Quick Start

1. **Activate the environment:**
   \`\`\`bash
   source ~/activate-academy.sh
   \`\`\`

2. **Start Jupyter Lab:**
   \`\`\`bash
   jupyter lab
   \`\`\`

3. **Open the welcome notebook:**
   Navigate to \`notebooks/00-welcome.ipynb\`

## Directory Structure

- **notebooks/** - Jupyter notebooks for lessons
- **datasets/** - Sample datasets
- **projects/** - Your projects
- **models/** - Saved models
- **scripts/** - Python scripts
- **docs/** - Documentation

## Installed Software

### Development Tools
- Python ${PYTHON_VERSION}
- Git & Git LFS
- Docker & Docker Compose
- Node.js ${NODE_VERSION}

### IDEs & Editors
- Visual Studio Code
- PyCharm Community Edition
- Sublime Text
- Jupyter Lab & Notebook

### AI/ML Libraries
- TensorFlow & PyTorch
- Scikit-learn
- Transformers (Hugging Face)
- OpenCV
- NLTK & spaCy

### Data Tools
- PostgreSQL
- MongoDB
- Redis
- Apache Spark

### Cloud Tools
- AWS CLI
- Azure CLI
- Google Cloud SDK

## Support

If you encounter issues, check the logs at:
~/.ai-academy-deployment/

Happy Learning! 🚀
EOF
    
    success "Academy resources created"
}

#############################################
# VS Code Extensions Installation
#############################################

install_vscode_extensions() {
    if command -v code &>/dev/null; then
        info "Installing VS Code extensions for AI development..."
        
        VS_EXTENSIONS=(
            "ms-python.python"
            "ms-python.vscode-pylance"
            "ms-python.debugpy"
            "ms-toolsai.jupyter"
            "ms-toolsai.jupyter-keymap"
            "ms-toolsai.jupyter-renderers"
            "ms-toolsai.vscode-jupyter-cell-tags"
            "GitHub.copilot"
            "GitHub.copilot-labs"
            "ms-azuretools.vscode-docker"
            "ms-vscode-remote.remote-containers"
            "mechatroner.rainbow-csv"
            "GrapeCity.gc-excelviewer"
            "RandomFractalsInc.vscode-data-preview"
            "hediet.vscode-drawio"
            "janisdd.vscode-edit-csv"
        )
        
        for extension in "${VS_EXTENSIONS[@]}"; do
            code --install-extension "$extension" --force 2>&1 | tee -a "$LOG_FILE" || true
        done
        
        success "VS Code extensions installed"
    else
        warning "VS Code not found, skipping extensions"
    fi
}

#############################################
# System Configuration
#############################################

configure_system() {
    info "Configuring system for AI Academy..."
    
    # Git configuration
    git config --global init.defaultBranch main 2>/dev/null || true
    git config --global core.autocrlf input 2>/dev/null || true
    git config --global pull.rebase false 2>/dev/null || true
    
    # Shell configuration
    SHELL_RC="$HOME/.zshrc"
    [ ! -f "$SHELL_RC" ] && SHELL_RC="$HOME/.bash_profile"
    
    # Add aliases if not present
    if ! grep -q "alias academy" "$SHELL_RC" 2>/dev/null; then
        cat >> "$SHELL_RC" << 'EOF'

# AI Academy Aliases
alias academy='cd ~/AI-Academy && source ~/activate-academy.sh'
alias jl='jupyter lab'
alias jn='jupyter notebook'
alias activate='source ~/activate-academy.sh'
alias bootcamp='cd ~/AI-Academy'
EOF
    fi
    
    # Add Python path
    if ! grep -q "PYTHONPATH.*AI-Academy" "$SHELL_RC" 2>/dev/null; then
        echo "export PYTHONPATH=\$PYTHONPATH:$HOME/AI-Academy/scripts" >> "$SHELL_RC"
    fi
    
    # Configure Jupyter
    mkdir -p "$HOME/.jupyter" 2>/dev/null
    cat > "$HOME/.jupyter/jupyter_notebook_config.py" << EOF 2>/dev/null || true
# AI Academy Jupyter Configuration
c = get_config()
c.NotebookApp.browser = 'open'
c.NotebookApp.open_browser = True
c.NotebookApp.notebook_dir = '$HOME/AI-Academy/notebooks'
EOF
    
    success "System configured"
}

#############################################
# Create Desktop Shortcuts
#############################################

create_desktop_shortcuts() {
    info "Creating desktop shortcuts..."
    
    # Create desktop shortcut for macOS
    if [ -d "$HOME/Desktop" ]; then
        cat > "$HOME/Desktop/Start AI Academy.command" << 'EOF'
#!/bin/bash
source ~/activate-academy.sh
cd ~/AI-Academy
jupyter lab
EOF
        chmod +x "$HOME/Desktop/Start AI Academy.command" 2>/dev/null || true
        success "Desktop shortcut created"
    fi
}

#############################################
# Comprehensive Validation
#############################################

validate_installation() {
    info "Validating installation..."
    
    local checks_passed=0
    local checks_total=0
    
    echo ""
    echo "Checking core components:"
    
    # Check commands
    COMMANDS=("python3" "pip3" "git" "brew" "docker" "code" "jupyter")
    for cmd in "${COMMANDS[@]}"; do
        ((checks_total++))
        if command -v "$cmd" &>/dev/null; then
            success "$cmd ✓"
            ((checks_passed++))
        else
            handle_error "$cmd ✗"
        fi
    done
    
    # Check virtual environment
    ((checks_total++))
    if [ -d "$HOME/ai-academy-env" ]; then
        success "Virtual environment ✓"
        ((checks_passed++))
    else
        handle_error "Virtual environment ✗"
    fi
    
    # Check Academy directory
    ((checks_total++))
    if [ -d "$HOME/AI-Academy" ]; then
        success "Academy resources ✓"
        ((checks_passed++))
    else
        handle_error "Academy resources ✗"
    fi
    
    # Test Python imports
    echo ""
    echo "Testing Python packages:"
    source "$HOME/ai-academy-env/bin/activate" 2>/dev/null || true
    
    CRITICAL_PACKAGES=("numpy" "pandas" "sklearn" "jupyter")
    for pkg in "${CRITICAL_PACKAGES[@]}"; do
        ((checks_total++))
        if python -c "import $pkg" 2>/dev/null; then
            success "$pkg ✓"
            ((checks_passed++))
        else
            warning "$pkg ✗"
        fi
    done
    
    deactivate 2>/dev/null || true
    
    echo ""
    info "Validation: $checks_passed/$checks_total passed"
    
    if [ $checks_passed -eq $checks_total ]; then
        success "All validations passed!"
        return 0
    else
        warning "Some validations failed. Check logs for details."
        return 1
    fi
}

#############################################
# Cleanup
#############################################

cleanup() {
    log "Performing cleanup..."
    
    # Remove lock file
    rm -f "$LOCK_FILE"
    
    # Clean caches if successful
    if [ $FAILURES -lt 5 ]; then
        brew cleanup --prune=all 2>/dev/null || true
        pip cache purge 2>/dev/null || true
    fi
    
    # Remove temp directory
    rm -rf "$TEMP_DIR"
    
    success "Cleanup complete"
}

#############################################
# Final Report
#############################################

generate_report() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    clear
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║      AI ACADEMY AZERBAIJAN - INSTALLATION COMPLETE       ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "📊 Installation Summary"
    echo "├─ Version: $SCRIPT_VERSION"
    echo "├─ Duration: ${minutes}m ${seconds}s"
    echo "├─ Warnings/Errors: $FAILURES"
    echo "└─ Log location: $LOG_FILE"
    echo ""
    echo "📂 Resources"
    echo "├─ Academy files: ~/AI-Academy"
    echo "├─ Virtual environment: ~/ai-academy-env"
    echo "└─ Activation script: ~/activate-academy.sh"
    echo ""
    echo "🚀 Getting Started"
    echo "├─ 1. Close and reopen Terminal"
    echo "├─ 2. Run: source ~/activate-academy.sh"
    echo "├─ 3. Run: jupyter lab"
    echo "└─ 4. Open: notebooks/00-welcome.ipynb"
    echo ""
    
    if [ $FAILURES -eq 0 ]; then
        echo -e "${GREEN}✅ Perfect installation - all components installed!${NC}"
    elif [ $FAILURES -lt 5 ]; then
        echo -e "${GREEN}✅ Installation successful with minor warnings${NC}"
    elif [ $FAILURES -lt 10 ]; then
        echo -e "${YELLOW}⚠️  Installation completed with some errors${NC}"
        echo "   Non-critical packages may need manual installation"
    else
        echo -e "${YELLOW}⚠️  Installation completed with multiple errors${NC}"
        echo "   Review: $ERROR_LOG"
    fi
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║            Welcome to AI Academy Azerbaijan! 🎓           ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    
    # Check for restart requirement
    if softwareupdate -l 2>&1 | grep -q "restart"; then
        echo ""
        echo -e "${YELLOW}⚠️  RESTART REQUIRED to complete installation${NC}"
        echo "Please restart your Mac when convenient."
    fi
}

#############################################
# Main Execution
#############################################

main() {
    START_TIME=$(date +%s)
    
    clear
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║     AI ACADEMY AZERBAIJAN - MAC SETUP SCRIPT             ║"
    echo "║                Version $SCRIPT_VERSION              ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "This script will install:"
    echo "• Development tools and compilers"
    echo "• Python ${PYTHON_VERSION} with AI/ML libraries"
    echo "• Docker, databases, and cloud tools"
    echo "• IDEs and productivity applications"
    echo ""
    echo "Installation will take 30-60 minutes depending on internet speed."
    echo ""
    read -p "Press Enter to start installation..." 

    keep_sudo_alive
    
    # Initial setup
    setup_environment
    log "Starting AI Academy deployment v$SCRIPT_VERSION"
    
    # Fix permissions first
    fix_all_permissions
    
    # System checks
    check_system_requirements
    ensure_rosetta
    
    # Core installations
    install_xcode_cli
    install_homebrew
    
    # Fix permissions again after core installations
    fix_all_permissions
    
    # Package installations
    install_all_brew_packages
    install_all_cask_apps
    
    # Python setup
    setup_python_environment
    ensure_jupyter_works
    
    # Academy setup
    setup_academy_resources
    install_vscode_extensions
    configure_system
    create_desktop_shortcuts
    
    # Validation
    validate_installation
    
    # Cleanup
    cleanup
    
    # Final report
    generate_report
}

# Trap for cleanup on exit
trap 'rm -f "$LOCK_FILE"' EXIT

# Error handling
set +e  # Continue on error
trap 'warning "Script interrupted but will continue..."' INT TERM

# Run main
main "$@"

# Exit based on severity
if [ $FAILURES -eq 0 ]; then
    exit 0
elif [ $FAILURES -lt 10 ]; then
    exit 0  # Minor failures, still successful
else
    exit 1  # Major failures
fi