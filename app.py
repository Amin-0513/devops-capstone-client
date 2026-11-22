import os
import json
import socket
import hashlib
from datetime import datetime

import streamlit as st

SERVER_HOST = os.environ.get("SERVER_HOST", "server")
SERVER_PORT = int(os.environ.get("SERVER_PORT", 5000))
DATA_DIR = "/clientdata"


# ---------- Networking logic ----------

def receive_file(host, port):
    """Connect to the server, return (header dict, file bytes)."""
    with socket.create_connection((host, port), timeout=10) as sock:
        # Read the JSON header line
        buf = b""
        while b"\n" not in buf:
            chunk = sock.recv(1024)
            if not chunk:
                raise ConnectionError("Connection closed before header was received.")
            buf += chunk
        header_line, data = buf.split(b"\n", 1)
        header = json.loads(header_line.decode())

        # Read the remaining file bytes
        while len(data) < header["size"]:
            chunk = sock.recv(4096)
            if not chunk:
                break
            data += chunk
    return header, data


def save_file(filename, data):
    """Save with a timestamp so each received file is kept."""
    os.makedirs(DATA_DIR, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    name, ext = os.path.splitext(filename)
    path = os.path.join(DATA_DIR, f"{name}_{stamp}{ext}")
    with open(path, "wb") as f:
        f.write(data)
    return path


def sha256(data):
    return hashlib.sha256(data).hexdigest()


# ---------- User interface ----------

st.set_page_config(page_title="File Transfer Client", page_icon="📦", layout="centered")
st.title("📦 File Transfer Client")
st.caption("Receives a file from the server container and verifies its integrity.")

with st.sidebar:
    st.header("Server settings")
    host = st.text_input("Server host", SERVER_HOST)
    port = st.number_input("Server port", value=SERVER_PORT, step=1)

if st.button("Fetch file from server", type="primary", use_container_width=True):
    try:
        with st.spinner(f"Connecting to {host}:{port}..."):
            header, data = receive_file(host, int(port))

        path = save_file(header["filename"], data)
        expected = header["checksum"]
        actual = sha256(data)

        st.success(f"File received and saved to `{path}`")

        col1, col2 = st.columns(2)
        col1.metric("File size", f"{len(data)} bytes")
        col2.metric("Expected size", f"{header['size']} bytes")

        st.subheader("Integrity check (SHA-256)")
        st.code(f"Expected: {expected}\nActual:   {actual}")

        if actual == expected:
            st.success("✅ Checksum verified: the file is intact.")
        else:
            st.error("❌ Checksum mismatch: the file is corrupted.")

        with st.expander("Preview file contents"):
            st.text(data.decode(errors="replace"))

        st.download_button(
            "Download file",
            data=data,
            file_name=os.path.basename(path),
            mime="text/plain",
        )

    except (OSError, ConnectionError, json.JSONDecodeError) as e:
        st.error(f"Could not receive file: {e}")
        st.info("Make sure the server container is running and on the 'filenet' network.")

# ---------- Files already in the volume ----------

st.divider()
st.subheader("Files stored in /clientdata")

if os.path.isdir(DATA_DIR):
    files = sorted(os.listdir(DATA_DIR), reverse=True)
    if files:
        rows = []
        for name in files:
            full = os.path.join(DATA_DIR, name)
            with open(full, "rb") as f:
                content = f.read()
            rows.append({
                "File": name,
                "Size (bytes)": len(content),
                "SHA-256": sha256(content)[:16] + "...",
            })
        st.dataframe(rows, use_container_width=True, hide_index=True)
    else:
        st.write("No files received yet.")
else:
    st.write("Directory /clientdata does not exist yet.")