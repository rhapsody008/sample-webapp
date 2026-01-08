# --- STAGE 1: The Build Stage ---
FROM registry.ntnxlab.local/library/golang:1.23-alpine AS builder

WORKDIR /app

COPY main.go .
RUN go build -ldflags="-s -w" -o /app/app main.go

# --- STAGE 2: The Final, Minimal Runtime Stage ---
FROM registry.ntnxlab.local/library/alpine:latest

RUN adduser -D appuser
USER appuser

WORKDIR /home/appuser/

COPY --from=builder /app/app .

EXPOSE 8080
CMD ["./app"]