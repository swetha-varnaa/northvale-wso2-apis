"""Asks WSO2 Integrator's own language server for the designer flow model of a workflow, headless.
Usage: REQS='[["flowDesignService/getFlowModel",{"filePath":...,"startLine":{"line":N,"offset":0},"endLine":{"line":M,"offset":1}}]]' OUT=flow.json python3 check_designer_flow_model.py <project> <file.bal>
Then: python3 show_flow_model.py flow.json 2"""
import json, subprocess, sys, os, threading, time
LS="/Applications/WSO2 Integrator.app/Contents/Resources/app/extensions/wso2.ballerina/ls/ballerina-language-server-6.0.0.jar"
HOME="/Library/Ballerina/distributions/ballerina-2201.14.1"
PROJ=sys.argv[1]; FILES=sys.argv[2:]
import glob
cp=":".join([j for j in sorted(glob.glob(HOME+"/bre/lib/*.jar")) if not any(x in j for x in ("model-generator","flow-model","language-server-commons"))]+[LS])
java="/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home/bin/java"
p=subprocess.Popen([java,"-cp",cp,f"-Dballerina.home={HOME}","org.ballerinalang.langserver.launchers.stdio.Main"],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=open(os.environ.get("LSLOG","/dev/null"),"w"))
res={}
def reader():
    while True:
        h=b""
        while not h.endswith(b"\r\n\r\n"):
            c=p.stdout.read(1)
            if not c: return
            h+=c
        n=int([l for l in h.decode().split("\r\n") if l.lower().startswith("content-length")][0].split(":")[1])
        m=json.loads(p.stdout.read(n))
        if "id" in m and ("result" in m or "error" in m): res[m["id"]]=m
threading.Thread(target=reader,daemon=True).start()
i=[0]
def send(method,params,notify=False):
    m={"jsonrpc":"2.0","method":method,"params":params}
    if not notify: i[0]+=1; m["id"]=i[0]
    b=json.dumps(m).encode(); p.stdin.write(b"Content-Length: %d\r\n\r\n"%len(b)+b); p.stdin.flush()
    if notify: return None
    t=time.time()
    while i[0] not in res and time.time()-t<120: time.sleep(0.2)
    return res.get(i[0])
uri="file://"+PROJ
send("initialize",{"processId":None,"rootUri":uri,"capabilities":{},"workspaceFolders":[{"uri":uri,"name":"p"}]})
send("initialized",{},True)
for f in FILES:
    send("textDocument/didOpen",{"textDocument":{"uri":"file://"+f,"languageId":"ballerina","version":1,"text":open(f).read()}},True)
time.sleep(5)
out={}
for method,params in json.loads(os.environ["REQS"]):
    out[method+" "+str(params.get("startLine",""))]=send(method,params)
open(os.environ.get("OUT","/dev/stdout"),"w").write(json.dumps(out,indent=1))
p.kill()
