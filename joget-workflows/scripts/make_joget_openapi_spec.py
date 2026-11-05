import sys,json,yaml
d=yaml.safe_load(open(sys.argv[1]))
d['info']['description']=("WSO2 Integrator workflow Management API (ballerina/workflow 1.0.2, spec 0.9.0), edited for the Joget API Connector: "
 "concrete server, x-api-key security only, x-user-id and x-user-roles declared on every operation. Source: compiler-plugin workflow-management-openapi.yaml.")
d['servers']=[{'url':'http://localhost:8234/workflow','description':'Local. Change to the hosted runtime URL on migration.'}]
d['components']['securitySchemes']={'wso2WorkflowApiKey':{'type':'apiKey','in':'header','name':'x-api-key','description':'Value in ~/vexa-system/.secrets/env as WSO2_WORKFLOW_MGMT_API_KEY'}}
d['security']=[{'wso2WorkflowApiKey':[]}]
hdr=[{'name':'x-user-id','in':'header','required':False,'description':'Joget username, e.g. #currentUser.username#','schema':{'type':'string'}},
     {'name':'x-user-roles','in':'header','required':False,'description':'Comma-separated roles, e.g. APPROVER or WORKFLOW_ADMIN','schema':{'type':'string'}}]
n=0
for path,item in d['paths'].items():
    for m,op in item.items():
        if m not in ('get','post','put','delete','patch'): continue
        op.setdefault('tags',['workflow'])
        op['security']=[{'wso2WorkflowApiKey':[]}]
        ps=op.setdefault('parameters',[])
        names={p.get('name') for p in ps if isinstance(p,dict)}
        for h in hdr:
            if h['name'] not in names: ps.append(dict(h))
        n+=1
json.dump(d,open(sys.argv[2],'w'),indent=1)
print('operations',n)
# Connector fixes: flatten allOf, give untyped schemas a type, break the ActivityTreeNode cycle.
sc=d['components']['schemas']
def resolve(s):
    if '$ref' in s: return resolve(sc[s['$ref'].split('/')[-1]])
    if 'allOf' in s:
        out={'type':'object','properties':{},'required':[]}
        for part in s['allOf']:
            r=resolve(part); out['properties'].update(r.get('properties',{})); out['required']+=r.get('required',[])
        for k,v in s.items():
            if k!='allOf': out[k]=v
        if not out['required']: del out['required']
        return out
    return s
def fix(s):
    if not isinstance(s,dict): return s
    if 'allOf' in s: s=resolve(s)
    if not any(k in s for k in ('type','$ref','oneOf','anyOf')): s['type']='object'
    for k,v in list(s.get('properties',{}).items()): s['properties'][k]=fix(v)
    if 'items' in s: s['items']=fix(s['items'])
    return s
for name in list(sc): sc[name]=fix(sc[name])
sc['ActivityTreeNode']['properties']['children']={'type':'array','items':{'type':'object'}}
json.dump(d,open(sys.argv[2],'w'),indent=1)
