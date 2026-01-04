# --- STAGE 1: The Build Stage ---
# We use a large image that contains all the tools needed to compile our Go app.
FROM golang:1.23-alpine AS builder

# Set the working directory for the build process
WORKDIR /app

# Copy the application source code into the container
COPY main.go .

# Build the Go application
# -a: disable cgo, which makes the binary statically linked and truly independent
# -o: specifies the output file name
RUN go build -ldflags="-s -w" -o /app/app main.go

# --- STAGE 2: The Final, Minimal Runtime Stage ---
# We switch to an incredibly small 'scratch' or 'alpine' image for the final product.
# We'll use alpine because it's still tiny but includes a few basic utilities.
FROM alpine:latest

# The final image should use an unprivileged user for better security
RUN adduser -D appuser
USER appuser

# Set the working directory for the application
WORKDIR /home/appuser/

# Copy *only* the compiled binary from the 'builder' stage
# The 'from=builder' flag is the magic of multi-stage builds!
COPY --from=builder /app/app .

# Expose the port the app listens on
EXPOSE 8080

# Define the command to run the application
CMD ["./app"]