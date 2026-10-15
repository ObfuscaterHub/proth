local Step = require("prometheus.step");
local Ast = require("prometheus.ast");
local Scope = require("prometheus.scope");
local Parser = require("prometheus.parser");
local Enums = require("prometheus.enums");
local logger = require("logger");
local AntiTamper = Step:extend();
AntiTamper.Description = "Injects a multi-layer, Roblox-specific anti-tamper system. Requires a Roblox (Luau) environment - the generated code hard-fails if the 'game' global is unavailable, so this step is not suitable for non-Roblox Lua targets.";
AntiTamper.Name = "Anti Tamper";
AntiTamper.SettingsDescriptor = {
    UseDebug = {
        type = "boolean",
        default = true,
        description = "Include debug‑library checks (gethook, etc.). Recommended."
    },
    DiagnosticMode = {
        type = "boolean",
        default = false,
        description = "If true, returns a report table instead of erroring."
    }
}
function AntiTamper:init(settings)
    self.UseDebug = settings and settings.UseDebug ~= false
    self.DiagnosticMode = settings and settings.DiagnosticMode or false
end
function AntiTamper:apply(ast, pipeline)
    if pipeline.PrettyPrint then
        logger:warn(string.format("\"%s\" cannot be used with PrettyPrint, ignoring \"%s\"", self.Name, self.Name));
        return ast;
    end
    local antiTamperFunc = [=[
      local function a(b,c)local d=nil;local e=false;if c and type(debug)=="table"and type(debug.getinfo)=="function"then local a,b=pcall(debug.getinfo,1,"S")if a and b and b.source then e=(b.source:sub(1,1)=="=")end end;if c and type(debug)=="table"and type(debug.getinfo)=="function"then local a,b=pcall(debug.getinfo,1,"l")if a and type(b)=="table"then d=b.currentline end end;if not game or not game.GetService then return error("Tamper: Invalid environment",0)end;local f=pcall;local g=error;local h=getfenv;local h=setfenv;local h=debug;local i=string.dump;local j=rawget(_G,"hookfunction")~=nil or rawget(_G,"replaceclosure")~=nil;local function k(a)if type(i)~="function"then return true end;local a,b=f(i,a)if not a then return true end;return type(b)=="string"and#b>10 end;local a=k(a)if not a then return g("Tamper: function modified",0)end;if c and h then if type(h.gethook)=="function"then local a,b=f(h.gethook)if a and b~=nil then return g("Tamper: debug hook detected",0)end end end;do local a,b=pcall(os.clock)if a then for a=1,1e4 do end;local a,a=pcall(os.clock)local b=a and(a-b)or 0;if a and b>2 then return g("Tamper: execution slowed",0)end end end;if _VERSION~="Luau"then local a=getmetatable(_G)if a and(a.__index or a.__newindex)then return g("Tamper: global metatable hooked",0)end end;if i and _VERSION~="Luau"then local a=f(i,function()end)if not a then return g("Tamper: dump blocked (hooked)",0)end end;local a={hard_failures={},soft_signals={},passed={}}local f={"alignorientation_","animclip_","bit32_","brickcolor_","buffer_","bulkmoveto_","bxor_","c2_","callback_","cframe_","chat_","collectionservice_","connection_","coroutine_","debugid_","distributed_","encoding_","enum_","error_msg_","game_","get_service","getfullname_","getgenv_","getmetatable_","global_environment_","gsub_","guid_","guiservice_","heartbeat_","highlight_","humanoiddescription_","instance_","isa_","integer_","invalid_method_","json","lighting_","literal_compare_","localplayer_","lua_fn_","math_","membership_","meshpart_","metamethod_","networkclient_","once_","os_date_","overlapparams_","part_","physics_","physicservice_","playbackloudness_","proximityprompt_","raw_probe_","raw_roundtrip_","rawget_","rawlen_","rawset_","raycastparams_","region3int16_","renderstepped_","runservice_","sandbox_","screenpointtoray_","server_time_","service_","shared_","signal_","soundservice_","stats_","string_","table_freeze","textbounds_","tostring_","traceback_","two_connections_","typeof_","utf8_","vector3_","weldconstraint_","wrong_class_","xor_","xpcall_","GUF_CRASH_","closure_","corepackages_","debug_info_","debug_traceback_","encode_probe_","error_passthrough_","forbidden_global_","gameid_","getservice_accepts_","line_consistency_","metatable_not_locked","named_error_","nan_identity_","runtime_fingerprint_","getrawmetatable_"}local function g(a)if type(a)~="string"then return false end;for b,b in ipairs(f)do if a:sub(1,#b)==b then return true end end;return false end;local function f(b,c)local a=g(b)and a.soft_signals or a.hard_failures;a[#a+1]={check=b,value=c}end;local function g(b,c)a.soft_signals[#a.soft_signals+1]={check=b,value=c}end;local function g(b,c)a.passed[#a.passed+1]={check=b,value=c}end;if j then f("executor_hook_api_present",true)end;local function h(a,...)if type(a)~="function"then return false,"not a function"end;return pcall(a,...)end;local function i(a)if type(typeof)=="function"then local a,b=pcall(typeof,a)if a then return b end end;return type(a)end;local function j(a,b)return a[b]end;local function k(a,b,c)a[b]=c end;local k=bit32 or(type(bit)=="table"and bit)or nil;local l=k and k.bxor or function(a,b)local c,d=0,1;while a>0 or b>0 do local e,f=a%2,b%2;if e~=f then c=c+d end;a,b,d=math.floor(a/2),math.floor(b/2),d*2 end;return c end;local k=k and k.band or function(a,b)local c,d=0,1;while a>0 and b>0 do if a%2==1 and b%2==1 then c=c+d end;a,b,d=math.floor(a/2),math.floor(b/2),d*2 end;return c end;local function m(a,...)local b={}for c=1,select("#",...)do b[c]=string.char(k(l(select(c,...),a),255))end;return table.concat(b)end;local function n(a)local b={}local c=(#a*257)%65536;for d=1,#a do local a=string.byte(a,d)b[d]=string.format("%02x",l(a,k(c,255)))c=k(c*31+d,65535)end;return table.concat(b)end;local function o()local a=0/0;if a~=a then return true end;return false end;local function p()return 57005 end;local function q()return 123 end;local function q()return 1 end;local function r()return 2 end;local function s()error("__ntt_probe__",0)end;local function t(a)local b="??";local c,d=pcall(tostring,a)if c then b=d end;local c=k(math.floor(((tick and tick())or 0)*997),255)local a=string.format("%x:%s:%x",tonumber(a)or 0,b,c)pcall(function()error("",0)end)pcall(function()local a=coroutine.running()if a then coroutine.status(a)end end)pcall(function()if task and coroutine then local a=coroutine.running()if a then task.spawn(function()coroutine.status(a)end)end end end)return a end;local function k()local a=_G;if type(getgenv)=="function"then local b,c=pcall(getgenv)if b and type(c)=="table"then a=c end end;if type(a)~="table"then f("global_environment_is_not_table",type(a))return end;local b={"__LARRY_FAILOPEN_CHILD_LOOKUPS","__LARRY_FAILOPEN_MEMBER_INDEX","__LARRY_FAILOPEN_ENUM_MEMBERS","__LARRY_FAILOPEN_PROPERTY_TYPES","__LARRY_FAILOPEN_MEMBER_NEWINDEX","__LARRY_SKIP_ASYNC_EXECUTION","__LARRY_ARGV_DEBUG","__LARRY_CLI_CONFIG_ARG","__LARRY_TIMEOUT_SECONDS","__LARRY_MAX_SIMULATED_SECONDS","__LARRY_CALL_LOG_ENABLED","__LARRY_FUNCTION_LOG_ENABLED","__LARRY_PREMIUM","__LARRY_PREMIUM_USER","__LARRY_IS_PREMIUM","__larry_internal","__larry_native_string_pack_raw","__larry_native_string_unpack_raw","LARRY_CLI_CONFIG_PERSIST","LARRY_CALL_LOG_ENABLED_PERSIST","LARRY_FUNCTION_LOG_ENABLED_PERSIST"}for b,b in ipairs(b)do local a=rawget(a,b)if a~=nil then if e then f("loadstring_forbidden:"..b,i(a))else f("forbidden_global_present:"..b,i(a))end else g("forbidden_global_absent:"..b,true)end end;for a in pairs(a)do if type(a)=="string"then local b=string.lower(a)if string.sub(b,1,10)=="__larry__"or string.sub(b,1,8)=="b_larry_"or string.find(b,"larry",1,true)==1 then f("forbidden_global_pattern:"..a,true)end end end end;local function u()if not c then return end;if type(debug)~="table"then g("debug_table_unavailable",true)return end;if type(debug.gethook)~="function"then g("debug_gethook_unavailable",true)return end;local a=nil;if type(coroutine)=="table"and type(coroutine.running)=="function"then local b,c=pcall(coroutine.running)if b then a=c end end;local b,c,d,e;if a~=nil then b,c,d,e=pcall(debug.gethook,a)else b,c,d,e=pcall(debug.gethook)end;if not b then f("debug_gethook_failed",c)return end;if c~=nil then f("debug_hook_installed",{hook_type=type(c),mask=d,count=e})else g("debug_hook_absent",true)end end;local function v()if not c then return end;if e then return end;if type(d)~="number"or d<=0 then g("line_consistency_unavailable",true)return end;if type(debug)~="table"or type(debug.getinfo)~="function"then g("line_consistency_debug_unavailable",true)return end;local a,b=pcall(debug.getinfo,1,"l")if not a or type(b)~="table"then f("line_consistency_probe_failed",b)return end;if b.currentline~=d then f("line_consistency_mismatch",{expected=d,actual=b.currentline})else g("line_consistency_valid",true)end end;local function c()if type(coroutine)~="table"then f("coroutine_table_missing",type(coroutine))return end;if type(coroutine.running)~="function"then f("coroutine_running_missing",type(coroutine.running))return end;if type(coroutine.status)~="function"then f("coroutine_status_missing",type(coroutine.status))return end;local a,b=pcall(coroutine.running)if not a then f("coroutine_running_failed",b)return end;if b==nil then g("coroutine_has_no_thread",true)return end;local a,b=pcall(coroutine.status,b)if not a then f("coroutine_status_failed",b)return end;if b~="running"then f("current_coroutine_not_running",b)else g("current_coroutine_running",true)end end;local function d(a,b)local a,c=h(a.GetService,a,b)if not a then f("get_service_failed:"..b,c)return nil end;return c end;local function d(a,b,c)local d=i(b)if d~="Instance"then f("service_not_instance:"..a,d)return false end;local d=nil;local e,h=pcall(j,b,"ClassName")if e then d=h end;if d~=c then f("wrong_class_name:"..a,d)return false end;if type(b.IsA)=="function"then local b,c=pcall(b.IsA,b,c)if not b or c~=true then f("isa_failed:"..a,c)return false end end;g("valid_instance:"..a,c)return true end;local function d()local a=game;if a==nil then f("game_missing",nil)return nil end;if type(a.GetService)~="function"then f("game_getservice_missing",type(a.GetService))return nil end;if i(a)~="Instance"then f("game_not_instance",i(a))end;local b=nil;local c,d=pcall(j,a,"ClassName")if c then b=d end;if b~="DataModel"then f("game_wrong_class",b)else g("game_is_datamodel",true)end;local b=pcall(function()do local a=Instance.new("TerrainRegion")assert(typeof(a)=="Instance")assert(a.ClassName=="TerrainRegion")assert(a:IsA("TerrainRegion"))assert(a:IsA("Instance"))local a=workspace:FindFirstChildOfClass("Terrain")if a then local a,b=pcall(function()return a:CopyRegion(Region3.new(Vector3.new(0,0,0),Vector3.new(4,4,4)))end)if a and b then assert(typeof(b)=="TerrainRegion")assert(b.ClassName=="TerrainRegion")assert(b:IsA("TerrainRegion"))local a=b.Size;assert(typeof(a)=="Vector3int16")assert(type(a.X)=="number")assert(type(a.Y)=="number")assert(type(a.Z)=="number")end end;local a=pcall(function()local a=Instance.new("Part")local b=a.Position;a:Destroy()end)assert(a)end end)if not b then f("terrainregion_probe_failed",true)else g("terrainregion_probe_ok",true)end;return{game=a}end;local function w(a)if a~=nil and type(a.Destroy)=="function"then pcall(a.Destroy,a)end end;local function w()local a={"KeyCode","UserInputType","UserInputState","Material","PartType","SurfaceType","NormalId","Axis","Font","FontWeight","FontStyle","TextXAlignment","TextYAlignment","AutomaticSize","FillDirection","HorizontalAlignment","VerticalAlignment","SortOrder","EasingStyle","EasingDirection","PlaybackState","CameraType","CameraMode","HumanoidStateType","HumanoidRigType","AnimationPriority","RaycastFilterType","PathStatus","PathWaypointAction","ActuatorRelativeTo","OrientationAlignmentMode","PositionAlignmentMode","ScaleType","ResamplerMode","ApplyStrokeMode","LineJoinMode","ScrollingDirection","ElasticBehavior","ScreenInsets","ZIndexBehavior","CoreGuiType","MouseBehavior","DevComputerMovementMode","DevTouchMovementMode","ComputerCameraMovementMode","TouchCameraMovementMode","ChatVersion","CreatorType","InfoType","ProductPurchaseDecision"}if i(Enum)~="Enums"then f("enum_root_invalid",i(Enum))return end;for a,a in ipairs(a)do local b,c=pcall(j,Enum,a)if not b or i(c)~="Enum"then f("enum_type_invalid:"..a,i(c))elseif type(c.GetEnumItems)~="function"then f("enum_getitems_missing:"..a,type(c.GetEnumItems))else local b,d=pcall(c.GetEnumItems,c)local e=nil;if b and type(d)=="table"then e=d[1]end;if not b then f("enum_getitems_failed:"..a,d)elseif i(e)~="EnumItem"then f("enum_first_item_invalid:"..a,i(e))elseif e.EnumType~=c then f("enum_item_wrong_owner:"..a,true)else g("enum_valid:"..a,tostring(e))end end end end;local function i()if type(rawget)~="function"then f("rawget_missing",type(rawget))return end;if type(rawset)~="function"then f("rawset_missing",type(rawset))return end;local a=_G;if type(getgenv)=="function"then local b,c=pcall(getgenv)if b and type(c)=="table"then a=c end end;if type(a)~="table"then f("raw_probe_environment_invalid",type(a))return end;local b="\1_kf"..tostring({})local c=25117;local d,e=pcall(rawset,a,b,c)local h,i=pcall(rawget,a,b)pcall(rawset,a,b,nil)if not d then f("rawset_probe_failed",e)elseif not h then f("rawget_probe_failed",i)elseif i~=c then f("raw_roundtrip_changed",i)else g("raw_roundtrip_valid",true)end end;local function j()local a=tostring(pcall)local b=tostring(pcall)if a~=b then f("pcall_identity_unstable",b)else g("pcall_identity_stable",true)end;local a=tostring(xpcall)local b=tostring(xpcall)if a~=b then f("xpcall_identity_unstable",b)else g("xpcall_identity_stable",true)end;local a,b=pcall(p)if not a or b~=57005 then f("closure_a_value_wrong",b)else g("closure_a_value_valid",true)end;local a,b=pcall(s)if a or type(b)~="string"or not string.find(b,"__ntt_probe__",1,true)then f("named_error_not_preserved",b)else g("named_error_preserved",true)end;local a=rawget(_G,"isfunctionhooked")if type(a)=="function"then local b={pcall,xpcall,tostring,type,rawget,rawset,setmetatable,getmetatable}local c=false;for b,b in ipairs(b)do if type(b)=="function"and a(b)then f("native_function_hooked",tostring(b))c=true;break end end;if not c then g("native_functions_not_hooked",true)end else g("isfunctionhooked_absent",true)end;local a=rawget(_G,"getgenv")if type(a)=="function"then local a,b=pcall(a)if a and type(b)=="table"then local a={}b[a]=true;if rawget(b,a)~=true then f("getgenv_rawset_roundtrip_failed",true)else g("getgenv_rawset_roundtrip_valid",true)end;b[a]=nil else f("getgenv_call_failed",a)end else g("getgenv_absent",true)end;if type(debug)=="table"and type(debug.info)=="function"then local a,b=pcall(debug.info,1,"s")if not a or type(b)~="string"then f("debug_info_returned_non_string",b)else g("debug_info_source_valid",true)end else g("debug_info_unavailable",true)end;local a=setmetatable({},{})local a=getmetatable(a)if a==nil then f("getmetatable_always_nil",true)else g("getmetatable_roundtrip_valid",true)end;local a=rawget(_G,"clonefunction")if type(a)=="function"then local a,b=pcall(a,pcall)if a and b==pcall then f("clonefunction_returned_same_ref",true)else g("clonefunction_distinct",true)end else g("clonefunction_absent",true)end;local a=rawget(_G,"getcallingscript")if type(a)=="function"then local a,b=pcall(a)if a and b and typeof and typeof(script)=="Instance"and b~=script then f("getcallingscript_mismatch",tostring(b))else g("getcallingscript_valid",true)end else g("getcallingscript_absent",true)end;local a=rawget(_G,"hookfunction")if type(a)=="function"then pcall(a,q,r)local a,b=pcall(q)if a and b==2 then f("hookfunction_active",b)else f("hookfunction_present_but_ineffective",b)end else g("hookfunction_absent",true)end;if not o()then f("nan_identity_broken",true)else g("nan_identity_valid",true)end;local a=t(42)if type(a)~="string"or#a==0 then f("runtime_fingerprint_empty",a)else g("runtime_fingerprint_valid",true)end;local a=n("antiTamper")local b=n("antiTamper")if a~=b or type(a)~="string"or#a==0 then f("encode_probe_string_nondeterministic",a)else g("encode_probe_string_valid",true)end;do local a=m(15,105,122,97,108,123,102,96,97)if a~="function"then f("xor_decode_wrong_output",a)else g("xor_decode_correct",true)end end;do local a,b=35,8659;local c=l(a,b)local c=l(c,b)if c~=a then f("bxor_roundtrip_broken",{a=a,b=b,got=c})else g("bxor_roundtrip_valid",true)end;if l(a,a)~=0 then f("bxor_self_cancel_broken",l(a,a))else g("bxor_self_cancel_valid",true)end end;do local a="__at_sandbox_"..tostring(math.random(1e9))local b=math.random(1e9)_G[a]=b;local c={}local d="__at_local_"..tostring(math.random(1e9))c[d]=true;setmetatable(c,{__index=_G,__newindex=function(a,b,c)if rawget(_G,b)~=nil then rawset(a,b,c)else _G[b]=c end end})local e=c[a];if e~=b then f("sandbox_env_read_through_broken",e)else g("sandbox_env_read_through_valid",true)end;local b="__at_newkey_"..tostring(math.random(1e9))c[b]=999;local e=rawget(_G,b)local h=rawget(c,b)if e~=999 or h~=nil then f("sandbox_env_new_write_wrong_target",{in_G=e,in_child=h})else g("sandbox_env_new_write_valid",true)end;c[d]=777;local d=rawget(c,d)if d~=777 then f("sandbox_env_local_write_broken",d)else g("sandbox_env_local_write_valid",true)end;_G[a]=nil;_G[b]=nil;setmetatable(c,nil)end;do local function a(a)return function(...)local a=coroutine.create(a)local a,b=coroutine.resume(a,...)if not a then error(b,2)end end end;local b=function()end;for c=1,198 do b=a(b)end;local a=pcall(b)if not a then f("coroutine_stack_depth_too_shallow",198)else g("coroutine_stack_depth_ok",198)end end;do local a,a=pcall(function()error(1)end)local b,b=pcall(function()error(2)end)local a=string.match(tostring(a),"%d+")local b=string.match(tostring(b),"%d+")if not a or not b then f("error_passthrough_no_digits",{v1=tostring(a),v2=tostring(b)})elseif a==b then f("error_passthrough_values_identical",a)else g("error_passthrough_distinct",{v1=a,v2=b})end end;if type(debug)=="table"and type(debug.info)=="function"then local function a(a,b,c)if type(a)~="function"then f("native_source_not_function:"..b,type(a))return end;local a,d=pcall(debug.info,a,"s")if not a then f("native_source_probe_failed:"..b,d)return end;if d=="[C]"or d=="=[C]"or d=="C"or d==nil then g("native_source_is_C:"..b,true)else if c then f("native_source_replaced:"..b,d)else f("native_source_wrapped:"..b,d)end end end;if not e then a(error,"error",true)a(tostring,"tostring",true)a(type,"type",true)a(rawget,"rawget",true)a(rawset,"rawset",true)a(xpcall,"xpcall",false)a(select,"select",false)a(setmetatable,"setmetatable",false)a(getmetatable,"getmetatable",false)a(string.byte,"string.byte",false)a(string.find,"string.find",false)a(string.format,"string.format",false)a(table.concat,"table.concat",false)a(math.floor,"math.floor",false)else end else g("native_source_check_skipped_no_debug_info",true)end end;k()u()v()c()d()w()i()j()local function c()local a=_G;if type(getfenv)=="function"then local b,c=pcall(getfenv,1)if b and type(c)=="table"then a=c end end;local b=0;local c=0;local d=rawget(a,"game")or rawget(_G,"game")local e=rawget(a,"Instance")or rawget(_G,"Instance")local f=rawget(a,"Vector3int16")or rawget(_G,"Vector3int16")local g=rawget(a,"Part")or rawget(_G,"Part")local i=rawget(a,"CFrame")or rawget(_G,"CFrame")local a=rawget(a,"RaycastParams")or rawget(_G,"RaycastParams")local function j(a)local a,b=h(function()return a.ClassName end)if a then return b end;return nil end;local function k(a,b)local a,b=h(function()return a:GetService(b)end)if a then return b end;return nil end;local l=d~=nil and type(d)~="table"and j(d)=="DataModel";if l then b=b+1;c=c+73 else c=c+11 end;local l=false;local m=nil;if e~=nil and type(e.new)=="function"then local a,b=h(e.new,"Folder")if a then m=b;l=j(m)=="Folder"and m.Name=="Folder"end end;if l then b=b+1;c=c+106 else c=c+42 end;local d=d and k(d,"Players")or nil;local d=d~=nil and j(d)=="Players";if d then b=b+1;c=c+157 else c=c+61 end;local d=false;if f~=nil and type(f.new)=="function"then local a,b=h(f.new,1,2,3)if a and b then d=b.X==1 and b.Y==2 and b.Z==3 end end;if d then b=b+1;c=c+104 else c=c+29 end;local a=g~=nil or i~=nil or a~=nil;if a then b=b+1;c=c+497 else c=c+97 end;return b,c end;local function d()local a=0;local b=0;local c=debug;if type(c)~="table"then return 0,8 end;local function d(a,b)if type(c.info)~="function"then return nil end;local a,b=h(c.info,a,b)if a then return b end;return nil end;if type(c.info)=="function"then local c=d(c.info,"s")if c=="[C]"or c==nil then a=a+1 else b=b+1 end else b=b+1 end;if type(c.traceback)=="function"then local c=d(c.traceback,"s")if c=="[C]"or c==nil then a=a+1 else b=b+1 end else b=b+1 end;if type(pcall)=="function"then local c=d(pcall,"s")if c=="[C]"or c==nil then a=a+1 else b=b+1 end else b=b+1 end;if type(string)=="table"and type(string.match)=="function"then local c=d(string.match,"s")if c=="[C]"or c==nil then a=a+1 else b=b+1 end else b=b+1 end;if type(c.traceback)=="function"then local c,d=h(c.traceback)if c and type(d)=="string"then local c=1;for a in d:gmatch("\n")do c=c+1 end;if c>64 then b=b+1 else a=a+1 end else b=b+1 end end;local function c()return 1 end;local c=d(c,"l")if type(c)=="number"then a=a+1 else b=b+1 end;return a,b end;local function e()local a=_G;if type(getfenv)=="function"then local b,c=pcall(getfenv,1)if b and type(c)=="table"then a=c end end;local b={"hookfunction","hookfunc","restorefunction","isfunctionhooked","newcclosure","clonefunction","getgc","getregistry","getrawmetatable","setreadonly","WYNF_NO_VIRTUALIZE"}local c=0;for b,d in ipairs(b)do local a=rawget(a,d)or rawget(_G,d)if a~=nil then c=c+b*17 end end;return c end;local function f()local a=_G;if type(getfenv)=="function"then local b,c=pcall(getfenv,1)if b and type(c)=="table"then a=c end end;local b=0;if type(getfenv)~="function"then b=b+7 end;if type(setfenv)~="function"then b=b+11 end;if type(rawget)~="function"then b=b+13 end;if type(setmetatable)~="function"then b=b+19 end;local c=nil;local a,d=h(getmetatable,a)if a then c=d end;if type(c)=="table"then local a={"__index","__newindex","__namecall","__iter","__pairs","__ipairs","__len","__metatable","__tostring"}for a,d in ipairs(a)do if rawget(c,d)~=nil then b=b+a*23 end end end;return b end;local function h()local a,b=c()local c,d=d()local e=e()local f=f()local g=336113460;if a<4 then g=(g+b+624781371)%2147483647 end;if d>0 then g=(g+d*658175227+c)%2147483647 end;if e>0 then g=(g+e*425412217)%2147483647 end;if f>0 then g=(g+f*1885244899)%2147483647 end;local a=(688970746+1885244899+g)%4294967296;local b=392018361;if g~=336113460 or d>0 or e>0 or f>0 then b=(b+g+e+f+d)%2147483647 end;return{jm=g,J9=a,K7_88=b,valid=(g==336113460 and b==392018361)}end;g("key_validation_passed",true)local c=error;a.hard_failure_count=#a.hard_failures;a.soft_signal_count=#a.soft_signals;a.passed_count=#a.passed;a.blocked=a.hard_failure_count>0;if b then return a end;if a.blocked then c("invalid binary",0)end;return true end
    ]=]
    local useDebugStr = self.UseDebug and "true" or "false"
    local diagStr = self.DiagnosticMode and "true" or "false"
    local code = string.format([[
        do
            local _outer_err0 = error
            local function _tamper_kill(msg)
                -- print + hard hang instead of error(): error() can be
                -- silently swallowed by an outer pcall wrapping this whole
                -- script, but a while-true-do loop cannot be caught or
                -- skipped, so this is the actual point of no return.
                print(msg)
                while true do end
            end
            local diagnostic_mode = %s
            local use_debug = %s
            %s
            local function is_hooked(fn)
                if type(fn) ~= "function" then return true end
                if type(debug) ~= "table" then return false end
                if type(debug.info) == "function" then
                    local ok, src = pcall(debug.info, fn, "s")
                    if not ok then return false end
                    if src == nil then return false end
                    local native = src == "[C]" or src == "=[C]" or src == "C"
                    return not native
                elseif type(debug.getinfo) == "function" then
                    local ok, info = pcall(debug.getinfo, fn)
                    if not ok or type(info) ~= "table" then return false end
                    local native = info.what == "C" or info.source == "=[C]" or info.source == "[C]"
                    return not native
                end
                return false
            end
            if is_hooked(pcall) or is_hooked(error) then
                _tamper_kill("ObfuscatorHub:- Intregrity test failed")
            end
            local function secure_call()
                local ok, reason = pcall(anti_tamper, diagnostic_mode, use_debug)
                if not ok then
                    local message = tostring(reason)
                    if message == "invalid binary" or message:sub(1, 7) == "Tamper:" then
                        _tamper_kill("ObfuscatorHub:- Intregrity test failed")
                    end
                    return false
                end
                return true
            end
            secure_call()
            if not is_loadstring then
                task.spawn(function()
                    while true do
                        task.wait(2 + math.random())
                        secure_call()
                    end
                end)
                local __anti_ref = anti_tamper
                task.spawn(function()
                    while true do
                        task.wait(1)
                        if anti_tamper ~= __anti_ref then
                            _tamper_kill("ObfuscatorHub:- Intregrity test failed")
                        end
                    end
                end)
            end
            local function _fake_return_empty(_) return "" end
            local function _fake_is_admin()      return false end
            local function _fake_decrypt_key(cb, _)
                cb(); return ({})[1]
            end
            local _fake_config_mt_inner = {}
            local _fake_config_mt = setmetatable({}, {
                __index    = function(_, k) _fake_config_mt_inner(); return k end,
                __newindex = function(_, _, _) _fake_config_mt_inner() end,
            })
            local _expected_honeypot = {
                fake_decrypt_key  = _fake_decrypt_key,
                fake_is_admin     = _fake_is_admin,
                fake_config_mt    = _fake_config_mt,
                fake_vm_master_key = 3735928559,
            }
            local _honey_env = getfenv and (function()
                local ok, e = pcall(getfenv, 1); return (ok and type(e) == "table") and e or _G
            end)() or _G
            _honey_env.fake_decrypt_key   = _fake_decrypt_key
            _honey_env.fake_is_admin      = _fake_is_admin
            _honey_env.fake_config_mt     = _fake_config_mt
            _honey_env.fake_vm_master_key = 3735928559
            local function _at_noop()
                local r = 0; if r == 0 then r = 99 end; return r
            end
            if not is_loadstring then
                task.spawn(function()
                    while true do
                        task.wait(5)
                        local env = _honey_env
                        if env.fake_decrypt_key   ~= _expected_honeypot.fake_decrypt_key   then secure_call() end
                        if env.fake_is_admin      ~= _expected_honeypot.fake_is_admin       then secure_call() end
                        if env.fake_config_mt     ~= _expected_honeypot.fake_config_mt      then secure_call() end
                        if env.fake_vm_master_key ~= _expected_honeypot.fake_vm_master_key  then secure_call() end
                        if env.fake_decrypt_key   == nil
                        or env.fake_is_admin      == nil
                        or env.fake_config_mt     == false then
                            _at_noop()
                        end
                        if env.fake_decrypt_key ~= _expected_honeypot.fake_decrypt_key
                        or env.fake_is_admin    ~= _expected_honeypot.fake_is_admin
                        or env.fake_config_mt   ~= _expected_honeypot.fake_config_mt
                        or env.fake_vm_master_key ~= _expected_honeypot.fake_vm_master_key then
                            secure_call()
                        end
                    end
                end)
            end
        end
    ]], diagStr, useDebugStr, antiTamperFunc)
    local parsed = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 }):parse(code);
    local doStat = parsed.body.statements[1];
    doStat.body.scope:setParent(ast.body.scope);
    table.insert(ast.body.statements, 1, doStat);
    return ast;
end
return AntiTamper;
