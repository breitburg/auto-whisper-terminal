#!/bin/bash

# Configuration
INSTALL_DIR="$HOME/whisper"
SHELL_RC="$HOME/.$(basename $SHELL)rc"
MODEL_NAME="ggml-large-v3-turbo"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_NAME}.bin"
MLMODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_NAME}-encoder.mlmodelc.zip"
WHISPER_CPP_REPO="https://github.com/ggerganov/whisper.cpp.git"

# Create installation directory
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Check for required tools
for cmd in git cmake ffmpeg curl; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is not installed. Please install it first."
        exit 1
    fi
done

# Function to check if URL exists
check_url() {
    curl --output /dev/null --silent --head --fail "$1"
    return $?
}

# Function to check for CoreML model availability and setup
check_coreml_availability() {
    if [[ "$(uname)" == "Darwin" ]] && check_url "$MLMODEL_URL"; then
        return 0  # CoreML model is available
    fi
    return 1  # CoreML model is not available
}

# Function to download and setup model files
setup_model_files() {
    # Download the base model
    if [ ! -f "${MODEL_NAME}.bin" ]; then
        echo "Downloading the model..."
        curl -L "$MODEL_URL" -o "${MODEL_NAME}.bin"
    fi

    # Setup CoreML model if available
    if check_coreml_availability; then
        echo "CoreML model found, downloading..."
        curl -L "$MLMODEL_URL" -o "${MODEL_NAME}-encoder.mlmodelc.zip"
        unzip -o "${MODEL_NAME}-encoder.mlmodelc.zip"
        rm "${MODEL_NAME}-encoder.mlmodelc.zip"
        return 0
    fi
    return 1
}

# Setup model and determine if we should use CoreML
setup_model_files
USE_COREML=$?  # Get the return value of setup_model_files

# Clone and build whisper.cpp
if [ ! -f "whisper-cpp" ]; then
    echo "Building whisper.cpp..."
    git clone "$WHISPER_CPP_REPO" whisper.cpp-source
    cd whisper.cpp-source

    # Configure build based on CoreML availability
    if [[ "$(uname)" == "Darwin" && "$USE_COREML" -eq 0 ]]; then
        echo "Building with CoreML support..."
        cmake -B build -DWHISPER_COREML=1 -DBUILD_SHARED_LIBS=OFF
    else
        echo "Building without CoreML support..."
        cmake -B build -DBUILD_SHARED_LIBS=OFF
    fi

    # Build the project
    cmake --build build --config Release -j

    # Copy the standalone executable
    cp build/bin/whisper-cli "$INSTALL_DIR/whisper-cpp"
    cd ..
    rm -rf whisper.cpp-source
fi

# Create whisper.sh script
cat > "$INSTALL_DIR/whisper.sh" << 'EOL'
#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHISPER_PATH="$SCRIPT_DIR/whisper-cpp"
MODEL_PATH="$SCRIPT_DIR/ggml-large-v3-turbo.bin"

# Check dependencies
if [ ! -f "$WHISPER_PATH" ] || [ ! -f "$MODEL_PATH" ]; then
    echo "Error: whisper-cpp or model file not found"
    exit 1
fi

if [ $# -eq 0 ]; then
    echo "Usage: $0 input1.mov input2.mp3 input3.mp4 ..."
    exit 1
fi

for input_file in "$@"; do
    if [ ! -f "$input_file" ]; then
        echo "Warning: Input file '$input_file' not found, skipping..."
        continue
    fi

    input_file_abs="$(cd "$(dirname "$input_file")" && pwd)/$(basename "$input_file")"
    filename_noext="${input_file_abs%.*}"
    temp_wav="/tmp/$(basename "$filename_noext")_temp.wav"

    echo "Converting '$input_file' to WAV..."
    if ! ffmpeg -i "$input_file" -ar 16000 -ac 1 -c:a pcm_s16le -y "$temp_wav" 2>/dev/null; then
        echo "Error: Failed to convert '$input_file'"
        continue
    fi

    echo "Transcribing '$input_file'..."
    cd /tmp
    if ! "$WHISPER_PATH" -m "$MODEL_PATH" -f "$temp_wav" -otxt -pp -l auto; then
        echo "Error: Failed to transcribe '$input_file'"
        rm -f "$temp_wav"
        continue
    fi

    mv "${temp_wav}.txt" "${filename_noext}.txt" 2>/dev/null
    echo "Transcription saved to '${filename_noext}.txt'"
    rm -f "$temp_wav"
done
EOL

# Make whisper.sh executable
chmod +x "$INSTALL_DIR/whisper.sh"

# Add alias to shell configuration
if ! grep -q "alias whisper=" "$SHELL_RC"; then
    echo "alias whisper='$INSTALL_DIR/whisper.sh'" >> "$SHELL_RC"
    echo "Added whisper alias to $SHELL_RC"
    echo "Please run 'source $SHELL_RC' to enable the alias"
fi

echo "Installation complete! You can now use 'whisper' command to transcribe audio files."
