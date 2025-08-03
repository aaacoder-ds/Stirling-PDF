#!/bin/bash

# Copy the original tesseract-ocr files to the volume directory without overwriting existing files
echo "Copying original files without overwriting existing files"
mkdir -p /usr/share/tessdata
cp -rn /usr/share/tessdata-original/* /usr/share/tessdata

if [ -d /usr/share/tesseract-ocr/4.00/tessdata ]; then
        cp -r /usr/share/tesseract-ocr/4.00/tessdata/* /usr/share/tessdata || true;
fi

if [ -d /usr/share/tesseract-ocr/5/tessdata ]; then
        cp -r /usr/share/tesseract-ocr/5/tessdata/* /usr/share/tessdata || true;
fi

# Check if TESSERACT_LANGS environment variable is set and is not empty
if [[ -n "$TESSERACT_LANGS" ]]; then
  # Convert comma-separated values to a space-separated list
  SPACE_SEPARATED_LANGS=$(echo $TESSERACT_LANGS | tr ',' ' ')
  pattern='^[a-zA-Z]{2,4}(_[a-zA-Z]{2,4})?$'
  # Install each language pack
  for LANG in $SPACE_SEPARATED_LANGS; do
     if [[ $LANG =~ $pattern ]]; then
      apk add --no-cache "tesseract-ocr-data-$LANG"
     else
      echo "Skipping invalid language code"
     fi
  done
fi

# Ensure temp directory exists with correct permissions before running main init
mkdir -p /tmp/stirling-pdf || true
chown -R stirlingpdfuser:stirlingpdfgroup /tmp/stirling-pdf || true
chmod -R 755 /tmp/stirling-pdf || true

# Set server configuration for Spring Boot - FORCE binding to all interfaces
export JAVA_TOOL_OPTIONS="${JAVA_BASE_OPTS} ${JAVA_CUSTOM_OPTS} -Dserver.address=0.0.0.0 -Dserver.port=8080 -Dserver.bind-address=0.0.0.0"
echo "running with JAVA_TOOL_OPTIONS ${JAVA_TOOL_OPTIONS}"

# Update the user and group IDs as per environment variables
if [ ! -z "$PUID" ] && [ "$PUID" != "$(id -u stirlingpdfuser)" ]; then
    usermod -o -u "$PUID" stirlingpdfuser || true
fi

if [ ! -z "$PGID" ] && [ "$PGID" != "$(getent group stirlingpdfgroup | cut -d: -f3)" ]; then
    groupmod -o -g "$PGID" stirlingpdfgroup || true
fi
umask "$UMASK" || true

if [[ "$INSTALL_BOOK_AND_ADVANCED_HTML_OPS" == "true" && "$FAT_DOCKER" != "true" ]]; then
  echo "issue with calibre in current version, feature currently disabled on Stirling-PDF"
  #apk add --no-cache calibre@testing
fi

if [[ "$FAT_DOCKER" != "true" ]]; then
  /scripts/download-security-jar.sh
fi

if [[ -n "$LANGS" ]]; then
  /scripts/installFonts.sh $LANGS
fi

echo "Setting permissions and ownership for necessary directories..."
# Ensure temp directory exists and has correct permissions
mkdir -p /tmp/stirling-pdf || true
# Attempt to change ownership of directories and files
if chown -R stirlingpdfuser:stirlingpdfgroup $HOME /logs /scripts /usr/share/fonts/opentype/noto /configs /customFiles /pipeline /tmp/stirling-pdf /app.jar; then
	chmod -R 755 /logs /scripts /usr/share/fonts/opentype/noto /configs /customFiles /pipeline /tmp/stirling-pdf /app.jar || true
    # If chown succeeds, execute the command as stirlingpdfuser with FORCED server binding
    # Use a different approach - override the application's configuration
    echo "Starting Stirling-PDF with forced server binding to 0.0.0.0:8080"
    # Create a temporary application.properties file to override server binding
    cat > /tmp/application-override.properties << EOF
server.address=0.0.0.0
server.port=8080
server.bind-address=0.0.0.0
spring.main.web-application-type=servlet
EOF
    exec su-exec stirlingpdfuser java -Dspring.config.location=file:/tmp/application-override.properties -Dserver.address=0.0.0.0 -Dserver.port=8080 -Dserver.bind-address=0.0.0.0 -Dspring.main.web-application-type=servlet -jar /app.jar
else
    # If chown fails, execute the command without changing the user context
    echo "[WARN] Chown failed, running as host user"
    echo "Starting Stirling-PDF with forced server binding to 0.0.0.0:8080"
    # Create a temporary application.properties file to override server binding
    cat > /tmp/application-override.properties << EOF
server.address=0.0.0.0
server.port=8080
server.bind-address=0.0.0.0
spring.main.web-application-type=servlet
EOF
    exec java -Dspring.config.location=file:/tmp/application-override.properties -Dserver.address=0.0.0.0 -Dserver.port=8080 -Dserver.bind-address=0.0.0.0 -Dspring.main.web-application-type=servlet -jar /app.jar
fi
