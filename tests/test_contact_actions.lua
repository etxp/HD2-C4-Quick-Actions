local fixture=dofile('tests/contact_fixture.lua')
local function check(name,fn)fn();print('PASS '..name)end
check('contact matches either event side and calls only the owned impacted charge once',function()
    local s=fixture();local other=s.add(202,{foreign=true});local unowned=s.add(203,{owned=false})
    s.throw(100);local ours=s.add(201)
    s.events.contacts={s.collide(other),s.collide(unowned),s.collide(ours),s.collide(ours,0,'b')}
    s.controller.step(200);s.controller.step(200);s.controller.step(201)
    assert(not s.controller.disabled and #s.effects==1 and s.effects[1]==201)
end)
check('contact mode does not detonate before collision or from an end-contact event',function()
    local s=fixture();s.throw(0);local c=s.add(1);s.controller.step(200)
    s.events.contacts={s.collide(c,2)};s.controller.step(300);assert(#s.effects==0)
    s.events.contacts={s.collide(c,0,'b')};s.controller.step(400);assert(#s.effects==1)
end)
check('manual charges remain manual after switching selector to contact',function()
    local s=fixture();s.throw(0,'MANUAL');local c=s.add(1);s.controller.step(200)
    s.mode('CONTACT');s.events.contacts={s.collide(c)};s.controller.step(600)
    assert(not s.controller.disabled and #s.effects==0)
end)
check('contact charge stays armed after switching to manual, gun or interface',function()
    local s=fixture();s.throw(0);local c=s.add(1);s.controller.step(200);s.mode('MANUAL')
    s.u32(s.state+0x1c,1);s.put(s.avatar_flags+10,'\x40') -- weapon settings cannot cancel a thrown contact charge
    s.events.contacts={s.collide(c)};s.controller.step(600)
    assert(not s.controller.disabled and #s.effects==1)
end)
check('mixed manual/contact charges do not turn a single collision into batch detonation',function()
    local s=fixture();s.throw(0,'MANUAL');local manual=s.add(1);s.controller.step(200)
    s.throw(700,'CONTACT');local contact=s.add(2)
    s.events.contacts={s.collide(manual),s.collide(contact)};s.controller.step(1000)
    assert(not s.controller.disabled and #s.effects==1 and s.effects[1]==2)
end)
check('charges present before contact-mode throw are never armed retroactively',function()
    local s=fixture();local old=s.add(1);s.throw(100);local new=s.add(2)
    s.events.contacts={s.collide(old),s.collide(new)};s.controller.step(300)
    assert(#s.effects==1 and s.effects[1]==2)
end)
check('failed or expired throw does not arm a later unrelated charge',function()
    local s=fixture();s.mode('CONTACT');s.controller.prepare(0);local c=s.add(1)
    s.events.contacts={s.collide(c)};s.controller.step(300);assert(#s.effects==0)
    s=fixture();s.throw(0);s.controller.step(3000);c=s.add(2)
    s.events.contacts={s.collide(c)};s.controller.step(3100);assert(#s.effects==0)
end)
check('ambiguous simultaneous new charges fail without guessing ownership by position',function()
    local s=fixture();s.throw(0);local c=s.add(1);s.add(2)
    s.events.contacts={s.collide(c)};s.controller.step(200)
    assert(s.controller.disabled and #s.effects==0)
end)
for _,change in ipairs({'world','weapon','authority','unit','registry'})do
    check(change..' replacement revokes the projectile capability',function()
        local s=fixture();s.throw(0);local c=s.add(1);s.controller.step(200)
        if change=='world' then s.events.root=s.root+100
        elseif change=='weapon' then s.put(s.waddr+16,'\1')
        elseif change=='authority' then s.put(c.address+20,'\0')
        elseif change=='unit' then s.u32(c.address+12,c.unit+1)
        else s.ptr(s.xregistry,s.waddr)end
        s.events.contacts={s.collide(c)};s.controller.step(600);assert(#s.effects==0)
    end)
end
for _,failure in ipairs({'code','log','read','same'})do
    check(failure..' failure prevents the explosion call',function()
        local s=fixture();s.throw(0);local c=s.add(1);s.controller.step(200)
        s.events.contacts={s.collide(c)}
        if failure=='code' then s.bad_code=true
        elseif failure=='log' then s.log_failure=true
        elseif failure=='read' then s.api.read=function()return nil end
        else local orig=s.backend.tracked;s.backend.tracked=function(...)
            local v=orig(...);v.same=function()return false end;return v end end
        s.controller.step(600);assert(s.controller.disabled and #s.effects==0)
    end)
end
check('native detonation already requested is not requested again by collision',function()
    local s=fixture();s.throw(0);local c=s.add(1,{requested=true})
    s.events.contacts={s.collide(c)};s.controller.step(600)
    assert(not s.controller.disabled and #s.effects==0)
end)
check('entity generation reuse removes old arming state',function()
    local s=fixture();s.throw(0);local c=s.add(1);s.controller.step(200)
    s.charges={};s.rebuild();s.controller.step(300)
    c=s.add(1,{unit=0x500001});s.events.contacts={s.collide(c)};s.controller.step(600)
    assert(#s.effects==0)
end)
check('tracked reader handles many existing owned charges within a bounded snapshot',function()
    local s=fixture();for i=1,40 do s.add(i)end
    local cap=s.selected();assert(#cap.charges==40 and cap.same())
    s.u32(s.state+0x1c,1);local fresh=s.tracked(cap.lease);assert(#fresh.charges==40 and fresh.same())
end)
check('original impact and remote-call ABI forwarded unchanged',function()
    local ffi=require('ffi');local calls={};local nativeffi=ffi
    package.loaded.ffi=setmetatable({os='Windows',cast=function(kind,value)
        if kind:find('(*)',1,true)then return function(...)
            calls[#calls+1]={kind=kind,address=value,args={...}}
        end end
        return nativeffi.cast(kind,value)
    end},{__index=ffi})
    local n=dofile('src/ContactActions.lua')(0x10000,{contact_explode=0x200,contact_remote_owner=0x300})
    n.explode({manager=0x20000,id=17,invalid_source=0x7fff});n.remote(0x30000,29)
    package.loaded.ffi=ffi
    assert(calls[1].kind=='void (*)(void *, uint32_t, uint32_t, void *)')
    assert(calls[1].address==0x10200 and calls[1].args[2]==17 and calls[1].args[3]==0x7fff and calls[1].args[4]==nil)
    assert(calls[2].address==0x10300 and calls[2].args[2]==29)
end)

check('Manual-only throws do not start the physics event scanner',function()
    local s=fixture();local reads=0
    s.backend.events=function()reads=reads+1;error('manual must not poll physics')end
    s.throw(0,'MANUAL');s.add(1)
    for i=1,1000 do s.controller.step(i*16)end
    assert(reads==0 and next(s.controller.scopes)==nil and not s.controller.disabled)
end)
check('new Manual throw cancels an old unmatched Contact spawn window',function()
    local s=fixture();s.throw(0,'CONTACT');s.throw(200,'MANUAL')
    local c=s.add(1);s.events.contacts={s.collide(c)};s.controller.step(400)
    assert(#s.effects==0 and not s.controller.disabled and next(s.controller.scopes)==nil)
end)
check('Manual throw preserves a previously armed Contact charge',function()
    local s=fixture();s.throw(0,'CONTACT');local contact=s.add(1);s.controller.step(100)
    s.throw(200,'MANUAL');local manual=s.add(2)
    s.events.contacts={s.collide(manual),s.collide(contact)};s.controller.step(400)
    assert(#s.effects==1 and s.effects[1]==contact.id and not s.controller.disabled)
end)

check('Manual preparation skips planted-charge enumeration but airborne selection remains complete',function()
    local s=fixture();for i=1,40 do s.add(i)end;s.mode('MANUAL')
    local read=s.api.read;local registries=0
    s.api.read=function(at,n)if at==s.remote+0x10 then registries=registries+1 end;return read(at,n)end
    s.throw(0,'MANUAL');assert(registries==0 and not s.controller.disabled)
    local cap=s.selected();assert(registries>0 and #cap.charges==40 and cap.remote==s.remote and cap.same())
end)
check('quiet tracks poll events every phase and a matching impact never waits for retirement',function()
    local s=fixture();s.throw(0);local c=s.add(1);s.controller.step(100)
    local tracked=s.backend.tracked;local scans,events=0,0
    s.backend.tracked=function(...)scans=scans+1;return tracked(...)end
    s.backend.events=function()events=events+1;return s.events end
    s.events.contacts={s.collide(c,2),s.collide(0x600000)}
    s.controller.step(101);s.controller.step(101);s.controller.step(102)
    assert(scans==0 and events==3 and #s.effects==0)
    s.events.contacts={s.collide(c)};s.controller.step(103)
    assert(scans==2 and events==4 and #s.effects==1 and next(s.controller.scopes)==nil)
    s.controller.step(104);assert(events==4)
end)
check('pending spawn discovery samples both phases and captures a first-frame collision',function()
    local s=fixture();s.throw(0)
    local tracked=s.backend.tracked;local scans=0
    s.backend.tracked=function(...)scans=scans+1;return tracked(...)end
    s.controller.step(16);assert(scans==1)
    local c=s.add(1);s.events.contacts={s.collide(c)};s.controller.step(16)
    assert(scans==3 and #s.effects==1 and not s.controller.disabled)
end)
check('quiet despawned tracks retire within the bounded maintenance interval',function()
    local s=fixture();s.throw(0);s.add(1);s.controller.step(100)
    s.charges={};s.rebuild();s.controller.step(349)
    assert(next(s.controller.scopes)~=nil)
    s.controller.step(350);assert(next(s.controller.scopes)==nil and not s.controller.disabled)
end)
check('quiet weapon replacement retires and world changes immediately clear tracked state',function()
    local s=fixture();s.throw(0);s.add(1);s.controller.step(100)
    s.put(s.waddr+16,'\1');s.controller.step(350)
    assert(next(s.controller.scopes)==nil and not s.controller.disabled)
    s=fixture();s.throw(0);s.add(1);s.controller.step(100)
    s.events.root=s.root+100;s.controller.step(101)
    assert(next(s.controller.scopes)==nil and not s.controller.disabled)
end)
check('same entity ID and unit reused before maintenance never inherit Contact mode',function()
    local s=fixture();s.throw(0);local c=s.add(1);s.controller.step(100)
    c.entity=s.entity(c.id,c.unit,true):sub(1,16)..'\18\0\0\0\1\0\0\0'
    s.rebuild();s.events.contacts={s.collide(c)};s.controller.step(101)
    assert(#s.effects==0 and next(s.controller.scopes)==nil and not s.controller.disabled)
end)
check('targeted collision validation does not scan unrelated planted charges',function()
    local s=fixture();local irrelevant={}
    for i=1,64 do irrelevant[#irrelevant+1]=s.add(i)end
    s.throw(0);local c=s.add(65);s.controller.step(100)
    local forbidden={};for _,charge in ipairs(irrelevant)do forbidden[charge.address]=true end
    local read=s.api.read
    s.api.read=function(at,n)assert(not forbidden[at],'unrelated_projectile_scan');return read(at,n)end
    s.events.contacts={s.collide(c)};s.controller.step(101)
    assert(#s.effects==1 and s.effects[1]==c.id and not s.controller.disabled)
end)
check('each collision call rebuilds identity after earlier native calls mutate the registry',function()
    local s=fixture();s.throw(0);local a=s.add(1);s.controller.step(100)
    s.throw(200);local b=s.add(2);s.controller.step(250)
    local explode=s.backend.explode
    s.backend.explode=function(cap)
        explode(cap)
        for _,c in ipairs(s.charges)do
            if c.id~=cap.id then c.entity=s.entity(c.id,c.unit+1,true) end
        end
        s.rebuild()
    end
    s.events.contacts={s.collide(a),s.collide(b)};s.controller.step(251)
    assert(#s.effects==1 and not s.controller.disabled)
end)
check('contact identity is rechecked after diagnostic callbacks and before native calls',function()
    local s=fixture();local c;local emit=s.emit
    s.controller=dofile('src/ContactController.lua').new(s.backend,function(kind,fields)
        if kind=='contact_detonate_call' then s.put(c.address+20,'\0') end
        return emit(kind,fields)
    end)
    s.throw(0);c=s.add(1);s.controller.step(100)
    s.events.contacts={s.collide(c)};s.controller.step(101)
    assert(#s.effects==0 and s.controller.disabled)
end)
check('unstable physics cannot keep a pending throw window alive indefinitely',function()
    local s=fixture();s.throw(0)
    s.backend.events=function()return nil,'event_stream_changed_during_read'end
    s.controller.step(2000);assert(next(s.controller.scopes)~=nil)
    s.controller.step(2001);assert(next(s.controller.scopes)==nil and not s.controller.disabled)
    local c=s.add(1);s.events.contacts={s.collide(c)}
    s.backend.events=function()return s.events end;s.controller.step(2100)
    assert(#s.effects==0)
end)
check('repeated completed Contact throws leave no retained track or unit maps',function()
    local s=fixture()
    for i=1,200 do
        s.throw(i*100);local c=s.add(i);s.events.contacts={s.collide(c)}
        s.controller.step(i*100+1)
        assert(#s.effects==i and next(s.controller.scopes)==nil and s.controller.prepared==nil)
        s.charges={};s.rebuild();s.events.contacts={}
    end
    assert(not s.controller.disabled)
end)
check('a transient native request never disarms an otherwise surviving Contact charge',function()
    local s=fixture();s.throw(0);local c=s.add(1);s.controller.step(100)
    c.requested=true;s.put(c.flag,'\1');s.events.contacts={s.collide(c)}
    s.controller.step(101);s.controller.step(350)
    assert(#s.effects==0 and next(s.controller.scopes)~=nil and not s.controller.disabled)
    c.requested=false;s.put(c.flag,'\0');s.controller.step(351)
    assert(#s.effects==1 and next(s.controller.scopes)==nil and not s.controller.disabled)
end)
check('a returned native call is one-shot across phases even if it leaves no requested flag',function()
    local s=fixture();s.throw(0);local c=s.add(1);s.controller.step(100)
    s.backend.explode=function(cap)s.effects[#s.effects+1]=cap.id end
    s.events.contacts={s.collide(c),s.collide(c,0,'b')}
    s.controller.step(101);s.controller.step(101);s.controller.step(102)
    assert(#s.effects==1 and next(s.controller.scopes)==nil and not s.controller.disabled)
    s.throw(200,'CONTACT');local another=s.add(2)
    s.events.contacts={s.collide(c),s.collide(another)};s.controller.step(250)
    assert(#s.effects==2 and s.effects[2]==another.id and not s.controller.disabled)
end)
local function scope_churn()
    -- Controller-level adversarial fixture: native identity checks themselves
    -- remain exercised above with ContactReader and mutable backing memory.
    local s={current=nil,live={},tracks={},calls=0,reads=0,events={root=1,contacts={}}}
    local backend={}
    s.backend=backend
    function backend.selected()
        return {lease={identity=tostring(s.current),root=1,weapon_id=s.current},mode='CONTACT',charges={}}
    end
    function backend.events()return s.events end
    function backend.tracked(lease,events,wanted)
        s.reads=s.reads+1
        return {expired=s.live[lease.weapon_id]==false,charges=s.tracks[lease.weapon_id] or {},same=function()return true end}
    end
    function backend.verify()end
    function backend.explode()s.calls=s.calls+1 end
    s.controller=dofile('src/ContactController.lua').new(backend,function()return true end)
    function s.throw(id,at)
        s.current=id;s.live[id]=true;s.controller.prepare(at);s.controller.commit(at)
        s.tracks[id]={{identity='charge_'..id,id=id,unit=1000+id}}
        s.controller.step(at+1)
    end
    return s
end
check('rapid weapon churn reclaims quiet despawned scopes before reaching the safety bound',function()
    local s=scope_churn()
    for id=1,5 do
        s.throw(id,id*20)
        assert(not s.controller.disabled)
        s.tracks[id]={};s.controller.step(id*20+2)
    end
    local n=0;for _ in pairs(s.controller.scopes)do n=n+1 end
    assert(n==1 and s.calls==0 and s.reads==9)
end)
check('budget reclamation preserves four live Contact scopes and rejects a fifth',function()
    local s=scope_churn()
    for id=1,4 do s.throw(id,id*20)end
    local n=0;for _ in pairs(s.controller.scopes)do n=n+1 end
    assert(n==4 and s.reads==4 and not s.controller.disabled)
    s.throw(5,100)
    assert(s.controller.disabled and s.reads==8 and s.calls==0)
end)
check('budget reclamation retains active scopes while retiring a checked expired weapon',function()
    local s=scope_churn()
    for id=1,4 do s.throw(id,id*20)end
    s.live[2]=false;s.throw(5,100)
    assert(not s.controller.disabled and s.controller.scopes['2']==nil)
    for _,id in ipairs({1,3,4,5})do assert(s.controller.scopes[tostring(id)])end
    assert(s.calls==0)
end)
local function enable_event_filter(s)
    local events=s.backend.events
    s.backend.events=function(units)
        s.last_unit_filter=units
        local source=events()
        if not units then return source end
        local filtered={root=source.root,contacts={}}
        for _,c in ipairs(source.contacts)do
            if units[c.unit_a] or units[c.unit_b]then filtered.contacts[#filtered.contacts+1]=c end
        end
        return filtered
    end
end
check('one known Contact scope reuses its unit index and keeps second-side impacts',function()
    local s=fixture();enable_event_filter(s);s.throw(0);s.controller.step(16)
    assert(s.last_unit_filter==nil)
    local c=s.add(1);s.controller.step(32)
    assert(s.last_unit_filter==nil)
    local _,scope=next(s.controller.scopes)
    s.events.contacts={s.collide(9000),s.collide(9001)};s.controller.step(48)
    assert(s.last_unit_filter==scope.units and #s.effects==0)
    s.events.contacts={s.collide(c,2,'b')};s.controller.step(48)
    assert(#s.effects==0 and not s.controller.disabled)
    s.events.contacts={s.collide(9000),s.collide(c,0,'b')};s.controller.step(49)
    assert(#s.effects==1 and s.effects[1]==c.id and not s.controller.disabled)
end)
check('multiple Contact scopes union their units without modifying individual ownership indexes',function()
    local s=scope_churn();enable_event_filter(s)
    for id=1,3 do s.throw(id,id*20)end
    s.controller.step(80)
    local units=s.last_unit_filter
    assert(units and units[1001] and units[1002] and units[1003] and not units[9000])
    for id=1,3 do
        local index=s.controller.scopes[tostring(id)].units;local count=0
        for _ in pairs(index)do count=count+1 end
        assert(count==1 and index[1000+id] and index~=units)
    end
    assert(not s.controller.disabled)
end)
check('any pending scope disables unit filtering so a newborn collision survives alongside older charges',function()
    local s=scope_churn();enable_event_filter(s);s.throw(1,20)
    local tracked=s.backend.tracked
    s.backend.tracked=function(lease,events,wanted)
        local cap=tracked(lease,events,wanted)
        for _,c in ipairs(cap.charges)do
            c.contact=nil
            for _,event in ipairs(events.contacts)do
                if event.unit_a==c.unit or event.unit_b==c.unit then c.contact=event end
            end
        end
        return cap
    end
    s.current=2;s.live[2]=true;s.controller.prepare(40);s.controller.commit(40)
    s.tracks[2]={{identity='charge_2',id=2,unit=1002}}
    s.events.contacts={{kind=0,unit_a=9000,unit_b=1002}}
    s.controller.step(41)
    assert(s.last_unit_filter==nil and s.calls==1 and not s.controller.disabled)
    assert(s.controller.scopes['1'] and not s.controller.scopes['2'])
end)
