# simple_asm_web_server
A simple web server written in x86 assembly

## Summary
This project implements a lightweight web server directly in x86-64 assembly language. It handles basic GET and POST requests, allowing file reading and writing without any dependencies on high-level languages or libraries.

## Features
- Minimal implementation with no external dependencies
- Handles concurrent connections via forking
- Supports GET requests to retrieve file contents
- Supports POST requests to write data to files

## Compiling
To compile the server, use the following commands:

```bash
# Assemble the source file
as -o server.o server.s

# Link the object file
ld -o server server.o
```

## Running the server
To run the server:

```bash
./server
```

**Note:** Since the server binds to port 80, you'll likely need root privileges to run it:

```bash
sudo ./server
```

> **Don't worry!** This is a simple, non-malicious web server that only reads and writes files as requested. You can review the assembly code to verify what it does. The sudo requirement is only because port 80 is a privileged port.

## Supported Requests

### GET Requests
The server handles GET requests to retrieve file contents. When you make a GET request with a file path, the server attempts to read the file at that exact path on the server's filesystem and returns its contents.

**Example:**
```bash
curl "http://localhost:80/path/to/your/file.txt"
```

### POST Requests
The server handles POST requests to write data to files. When you make a POST request with a file path and some data in the request body, the server will create or overwrite the file at that path with the provided content.

**Example:**
```bash
curl -X POST "http://localhost:80/path/to/save/data.txt" -d "This is some content to save"
```

## Request Examples

### Creating a file with POST:
```bash
curl -X POST "http://localhost:80/tmp/hello.txt" -d "Hello, world!"
```

### Reading the created file with GET:
```bash
curl "http://localhost:80/tmp/hello.txt"
```
Output:
```
Hello, world!
```
