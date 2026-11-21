# Receive soil readings sent over Thread (UDP port 50000), append them to ~/soil.log,
# and forward each one to the web app (POST /api/readings) when PLANTER_API_URL is set.
import socket, datetime, json, os, urllib.request

PORT = 50000
API_URL = os.environ.get("PLANTER_API_URL")      # e.g. https://planter.example.workers.dev
TOKEN = os.environ.get("PLANTER_TOKEN", "")
DEVICE = os.environ.get("PLANTER_DEVICE", "planter-1")

def parse(text):
    # "moisture=46 volt=1.9 raw=2161 status=ok" -> dict
    fields = dict(kv.split("=", 1) for kv in text.split() if "=" in kv)
    return {
        "device": DEVICE,
        "moisture": int(fields["moisture"]),
        "volt": float(fields["volt"]),
        "raw": int(fields["raw"]),
        "status": fields["status"],
    }

def forward(reading):
    req = urllib.request.Request(
        API_URL.rstrip("/") + "/api/readings",
        data=json.dumps(reading).encode(),
        headers={"Content-Type": "application/json", "Authorization": "Bearer " + TOKEN},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as res:
        return res.status

s = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("::", PORT))
log = os.path.expanduser("~/soil.log")
while True:
    data, addr = s.recvfrom(512)
    text = data.decode(errors="replace").strip()
    now = datetime.datetime.now().isoformat(timespec="seconds")
    line = now + " " + addr[0] + " " + text
    print(line, flush=True)
    with open(log, "a") as f:
        f.write(line + "\n")
    if API_URL:
        try:
            print("forwarded:", forward(parse(text)), flush=True)
        except Exception as e:
            print("forward failed:", e, flush=True)
