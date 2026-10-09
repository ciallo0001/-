import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { randomUUID, createHash } from 'node:crypto';
import pg from 'pg';

test('campus complete DDL and database authorization contract (temporary database only)', async t => {
  const url = new URL(process.env.ADMIN_DATABASE_URL);
  const name = 'campus_design_test_' + randomUUID().replaceAll('-','');
  const maintenance = new URL(url); maintenance.pathname='/postgres';
  const control = new pg.Client({connectionString:maintenance.toString()});
  await control.connect();
  let owner, backend, agent, created=false;
  const digest=s=>createHash('sha256').update(s).digest();
  const rejected=code=>error=>error.code===code;
  try {
    await control.query(`CREATE DATABASE "${name}" TEMPLATE template0`);created=true;
    await control.query(`REVOKE ALL ON DATABASE "${name}" FROM PUBLIC`);
    await control.query(`GRANT CONNECT ON DATABASE "${name}" TO app_backend,app_agent`);
    url.pathname='/'+name;
    owner=new pg.Client({connectionString:url.toString()});await owner.connect();
    await t.test('all tables, constraints, views and policies execute on PostgreSQL',async()=>{
      await owner.query(await readFile('db/design/campus-platform.full.sql','utf8'));
      const count=await owner.query("SELECT count(*)::int AS n FROM information_schema.tables WHERE table_schema='app' AND table_type='BASE TABLE'");
      assert.equal(count.rows[0].n,66);
    });
    const connect=async key=>{const u=new URL(process.env[key]);u.pathname='/'+name;const db=new pg.Client({connectionString:u.toString()});await db.connect();return db;};
    backend=await connect('BACKEND_DATABASE_URL');agent=await connect('AGENT_DATABASE_URL');
    const ids=Object.fromEntries(['admin','studentA','studentB','teacher','unverified','expired'].map(k=>[k,randomUUID()]));
    for(const [key,id] of Object.entries(ids)){
      const role=key==='admin'?'admin':key==='teacher'?'teacher':'student';
      await owner.query(`INSERT INTO app.users(id,email,password_hash,display_name,role,email_ciphertext,email_lookup)
        VALUES($1,$2,'test-hash-not-for-login',$3,$4,$5,$6)`,[id,id+'@private.invalid',key,role,Buffer.from('test-ciphertext'),digest(id)]);
    }
    for(const key of ['studentA','studentB','teacher','expired']){
      const id=ids[key],role=key==='teacher'?'teacher':'student';
      await owner.query(`INSERT INTO app.identity_verifications(user_id,identity_type,real_name_ciphertext,credential_lookup,status,verified_by,verified_at,expires_at)
        VALUES($1,$2,$3,$4,'verified',$5,now()-interval '2 days',CASE WHEN $6 THEN now()-interval '1 day' ELSE NULL END)`,[id,role,Buffer.from('test'),digest(id),ids.admin,key==='expired']);
    }
    for(const id of Object.values(ids)) {
      const proof=(await owner.query("SELECT id FROM app.identity_verifications WHERE user_id=$1 AND status='verified'",[id])).rows[0]?.id;
      await owner.query(`INSERT INTO app.auth_sessions(token_hash,user_id,csrf_token,expires_at,authenticated_identity_id,identity_authenticated_at,identity_valid_until)
        VALUES($1,$2,'test-csrf',now()+interval '1 day',$3,CASE WHEN $3::uuid IS NULL THEN NULL ELSE now() END,
          CASE WHEN $3::uuid IS NULL THEN NULL ELSE now()+interval '1 hour' END)`,[digest(id),id,proof??null]);
    }
    for(const key of ['studentA','studentB','unverified','expired'])await owner.query(`INSERT INTO app.student_profiles(user_id,student_no_ciphertext,student_no_lookup) VALUES($1,$2,$3)`,[ids[key],Buffer.from('test'),digest(key)]);
    await owner.query('INSERT INTO app.teacher_profiles(user_id,employee_no_ciphertext,employee_no_lookup) VALUES($1,$2,$3)',[ids.teacher,Buffer.from('test'),digest('teacher')]);
    const term=(await owner.query("INSERT INTO app.academic_terms(code,name,starts_on,ends_on) VALUES('2026-1','Term','2026-09-01','2027-01-31') RETURNING id")).rows[0].id;
    const course=(await owner.query("INSERT INTO app.courses(code,name) VALUES('CS101','Database') RETURNING id")).rows[0].id;
    const sectionA=(await owner.query("INSERT INTO app.class_sections(term_id,course_id,section_code) VALUES($1,$2,'A') RETURNING id",[term,course])).rows[0].id;
    const sectionB=(await owner.query("INSERT INTO app.class_sections(term_id,course_id,section_code) VALUES($1,$2,'B') RETURNING id",[term,course])).rows[0].id;
    await owner.query('INSERT INTO app.section_teachers(section_id,teacher_id) VALUES($1,$2)',[sectionA,ids.teacher]);
    for(const [key,section] of [['studentA',sectionA],['studentB',sectionB],['unverified',sectionA],['expired',sectionA]])await owner.query('INSERT INTO app.student_enrollments(section_id,student_id) VALUES($1,$2)',[section,ids[key]]);
    await owner.query('INSERT INTO app.class_schedules(section_id,weekday,start_period,period_count) VALUES($1,1,1,2),($2,2,1,2)',[sectionA,sectionB]);
    const exam=(await owner.query("INSERT INTO app.exams(section_id,title,starts_at) VALUES($1,'Final',now()) RETURNING id",[sectionA])).rows[0].id;
    await owner.query('INSERT INTO app.exam_scores(exam_id,section_id,student_id,score,published_at) VALUES($1,$2,$3,90,now()),($1,$2,$4,80,now()),($1,$2,$5,70,now())',[exam,sectionA,ids.studentA,ids.unverified,ids.expired]);
    const asUser=async(id,work,db=backend)=>{
      await db.query('BEGIN');
      try{await db.query("SELECT set_config('app.user_id',$1,true),set_config('app.session_hash',$2,true)",[id??'',id?digest(id).toString('hex'):'']);return await work(db);}
      finally{await db.query('ROLLBACK');}
    };
    await t.test('guest, unverified and expired users cannot see personal academic data',async()=>{
      for(const id of [null,ids.unverified,ids.expired])await asUser(id,async db=>{
        for(const table of ['exam_scores','class_schedules','student_profiles'])assert.equal((await db.query(`SELECT * FROM app.${table}`)).rowCount,0);
      });
    });
    await t.test('student sees only own published scores and own enrolled schedule',async()=>{
      await asUser(ids.studentA,async db=>{
        const scores=await db.query('SELECT student_id FROM app.exam_scores');assert.deepEqual(scores.rows.map(r=>r.student_id),[ids.studentA]);
        assert.deepEqual((await db.query('SELECT section_id FROM app.class_schedules')).rows.map(r=>r.section_id),[sectionA]);
      });
      await asUser(ids.studentB,async db=>{
        assert.equal((await db.query('SELECT * FROM app.exam_scores WHERE student_id=$1',[ids.studentA])).rowCount,0);
        assert.deepEqual((await db.query('SELECT section_id FROM app.class_schedules')).rows.map(r=>r.section_id),[sectionB]);
      });
      await owner.query('UPDATE app.exam_scores SET published_at=NULL WHERE student_id=$1',[ids.studentA]);
      await asUser(ids.studentA,async db=>assert.equal((await db.query('SELECT * FROM app.exam_scores')).rowCount,0));
      await owner.query('UPDATE app.exam_scores SET published_at=now() WHERE student_id=$1',[ids.studentA]);
    });
    await t.test('teacher sees own teaching schedule but no student scores',async()=>{
      await asUser(ids.teacher,async db=>{
        assert.equal((await db.query('SELECT * FROM app.exam_scores')).rowCount,0);
        assert.deepEqual((await db.query('SELECT section_id FROM app.class_schedules')).rows.map(r=>r.section_id),[sectionA]);
      });
    });
    await t.test('administrator cannot read student grades, private profiles or personal schedules',async()=>{
      await asUser(ids.admin,async db=>{
        for(const table of ['exam_scores','class_schedules','student_profiles','teacher_profiles'])assert.equal((await db.query(`SELECT * FROM app.${table}`)).rowCount,0);
      });
    });
    await t.test('current login requires valid identity proof and matching session owner',async()=>{
      await owner.query("UPDATE app.auth_sessions SET identity_authenticated_at=now()-interval '2 hours',identity_valid_until=now()-interval '1 hour' WHERE user_id=$1",[ids.studentA]);
      await asUser(ids.studentA,async db=>assert.equal((await db.query('SELECT * FROM app.exam_scores')).rowCount,0));
      await owner.query("UPDATE app.auth_sessions SET identity_authenticated_at=now(),identity_valid_until=now()+interval '1 hour' WHERE user_id=$1",[ids.studentA]);
      await asUser(ids.studentA,async db=>{
        await db.query("SELECT set_config('app.session_hash',$1,true)",[digest(ids.studentB).toString('hex')]);
        assert.equal((await db.query('SELECT * FROM app.exam_scores')).rowCount,0);
      });
      const otherProof=(await owner.query('SELECT id FROM app.identity_verifications WHERE user_id=$1',[ids.studentB])).rows[0].id;
      await assert.rejects(owner.query('UPDATE app.auth_sessions SET authenticated_identity_id=$1 WHERE user_id=$2',[otherProof,ids.studentA]),rejected('23503'));
    });
    await t.test('forged role setting cannot enable verification or alter grades',async()=>{
      await asUser(ids.unverified,async db=>{
        await db.query("SELECT set_config('app.user_role','admin',true)");
        assert.equal((await db.query('SELECT app.request_admin() AS ok')).rows[0].ok,false);
        assert.equal((await db.query("UPDATE app.identity_verifications SET status='verified' WHERE user_id=$1",[ids.unverified])).rowCount,0);
      });
      await assert.rejects(asUser(ids.studentA,db=>db.query('UPDATE app.exam_scores SET score=99')),rejected('42501'));
    });
    await t.test('disabled user loses academic access',async()=>{
      await owner.query("UPDATE app.users SET status='disabled' WHERE id=$1",[ids.studentA]);
      await asUser(ids.studentA,async db=>assert.equal((await db.query('SELECT * FROM app.exam_scores')).rowCount,0));
      await owner.query("UPDATE app.users SET status='active' WHERE id=$1",[ids.studentA]);
      await owner.query(`INSERT INTO app.auth_sessions(token_hash,user_id,csrf_token,expires_at,authenticated_identity_id,identity_authenticated_at,identity_valid_until)
        SELECT $1,user_id,'renewed-test-csrf',now()+interval '1 day',id,now(),now()+interval '1 hour'
        FROM app.identity_verifications WHERE user_id=$2`,[digest(ids.studentA),ids.studentA]);
    });
    await t.test('cross-section grades and scores beyond maximum are rejected',async()=>{
      await assert.rejects(owner.query('INSERT INTO app.exam_scores(exam_id,section_id,student_id,score) VALUES($1,$2,$3,80)',[exam,sectionA,ids.studentB]),rejected('23503'));
      await assert.rejects(owner.query('UPDATE app.exam_scores SET score=101 WHERE student_id=$1',[ids.studentA]),rejected('23514'));
      await assert.rejects(owner.query('UPDATE app.exams SET total_score=50 WHERE id=$1',[exam]),rejected('23514'));
      await assert.rejects(owner.query("UPDATE app.users SET role='teacher' WHERE id=$1",[ids.studentA]),rejected('23514'));
    });
    const anon=(await owner.query("INSERT INTO app.wall_posts(author_id,content,is_anonymous,status) VALUES($1,'Hello',true,'published') RETURNING id",[ids.studentA])).rows[0].id;
    await owner.query("INSERT INTO app.wall_comments(post_id,author_id,content,is_anonymous,status) VALUES($1,$2,'Comment',true,'published')",[anon,ids.studentA]);
    await t.test('anonymous public views never return author identity; raw tables hidden',async()=>{
      await asUser(null,async db=>{
        for(const view of ['wall_public_posts','wall_public_comments']){
          const r=await db.query(`SELECT * FROM app.${view}`);assert.equal(r.rowCount,1);assert.equal(r.rows[0].author_id,null);assert.equal(r.rows[0].display_name,'匿名用户');
        }
        assert.equal((await db.query('SELECT * FROM app.wall_posts')).rowCount,0);
      });
      await asUser(ids.studentB,async db=>assert.equal((await db.query('SELECT * FROM app.wall_posts')).rowCount,0));
    });
    await t.test('verified user comments need moderation and cannot impersonate another author',async()=>{
      await asUser(ids.studentB,async db=>{await db.query("INSERT INTO app.wall_comments(post_id,author_id,content) VALUES($1,$2,'reply')",[anon,ids.studentB]);});
      await assert.rejects(asUser(ids.studentB,db=>db.query("INSERT INTO app.wall_comments(post_id,author_id,content,status) VALUES($1,$2,'reply','published')",[anon,ids.studentB])),rejected('42501'));
      await assert.rejects(asUser(ids.studentB,db=>db.query("INSERT INTO app.wall_posts(author_id,content) VALUES($1,'fake')",[ids.studentA])),rejected('42501'));
    });
    const pair=[ids.studentA,ids.studentB].sort();
    const conversation=(await owner.query('INSERT INTO app.conversations(created_by,participant_a,participant_b) VALUES($1,$2,$3) RETURNING id',[ids.studentA,...pair])).rows[0].id;
    await owner.query('INSERT INTO app.conversation_members(conversation_id,user_id) VALUES($1,$2),($1,$3)',[conversation,...pair]);
    await asUser(ids.studentA,db=>db.query('INSERT INTO app.direct_messages(conversation_id,sender_id,body_ciphertext,client_message_id) VALUES($1,$2,$3,$4)',[conversation,ids.studentA,Buffer.from('secret'),randomUUID()]));
    // asUser rolls writes back, so seed the persistent message as the migration owner.
    await owner.query('INSERT INTO app.direct_messages(conversation_id,sender_id,body_ciphertext,client_message_id) VALUES($1,$2,$3,$4)',[conversation,ids.studentA,Buffer.from('secret'),randomUUID()]);
    await t.test('private messages have non-recursive member-only RLS; admin has no implicit access',async()=>{
      for(const id of pair)await asUser(id,async db=>assert.equal((await db.query('SELECT * FROM app.direct_messages')).rowCount,1));
      for(const id of [ids.admin,ids.teacher,null])await asUser(id,async db=>assert.equal((await db.query('SELECT * FROM app.direct_messages')).rowCount,0));
      await assert.rejects(owner.query('INSERT INTO app.conversation_members(conversation_id,user_id) VALUES($1,$2)',[conversation,ids.teacher]),rejected('23514'));
      await assert.rejects(asUser(ids.teacher,db=>db.query('INSERT INTO app.direct_messages(conversation_id,sender_id,body_ciphertext,client_message_id) VALUES($1,$2,$3,$4)',[conversation,ids.teacher,Buffer.from('forged'),randomUUID()])),rejected('23514'));
      await owner.query('INSERT INTO app.user_blocks(blocker_id,blocked_id) VALUES($1,$2)',pair);
      await assert.rejects(asUser(ids.studentA,db=>db.query('INSERT INTO app.direct_messages(conversation_id,sender_id,body_ciphertext,client_message_id) VALUES($1,$2,$3,$4)',[conversation,ids.studentA,Buffer.from('blocked'),randomUUID()])),rejected('23514'));
    });
    await t.test('Agent has only sanitized campus views, not private domain data',async()=>{
      assert.equal((await agent.query('SELECT * FROM app.wall_public_posts')).rows[0].author_id,null);
      for(const table of ['exam_scores','student_profiles','wall_posts','direct_messages','identity_verifications','shop_orders'])await assert.rejects(agent.query(`SELECT * FROM app.${table}`),rejected('42501'));
    });
    await t.test('public introduction and product publication rules; private orders isolated',async()=>{
      await owner.query("INSERT INTO app.campus_pages(slug,title,status,published_at) VALUES('intro','Intro','published',now()),('draft','Draft','draft',NULL)");
      const store=(await owner.query("INSERT INTO app.stores(name,store_type) VALUES('Food','snack_street') RETURNING id")).rows[0].id;
      const product=(await owner.query("INSERT INTO app.products(store_id,name,price_cents,stock_quantity) VALUES($1,'Tea',500,10) RETURNING id",[store])).rows[0].id;
      const order=(await owner.query('INSERT INTO app.shop_orders(buyer_id,store_id,total_cents,request_key) VALUES($1,$2,500,$3) RETURNING id',[ids.studentA,store,randomUUID()])).rows[0].id;
      await owner.query("INSERT INTO app.shop_order_items(order_id,store_id,product_id,product_name_snapshot,unit_price_cents,quantity) VALUES($1,$2,$3,'Tea',500,1)",[order,store,product]);
      await asUser(null,async db=>{assert.equal((await db.query('SELECT * FROM app.campus_public_pages')).rowCount,1);assert.equal((await db.query('SELECT * FROM app.public_products')).rowCount,1);assert.equal((await db.query('SELECT * FROM app.shop_orders')).rowCount,0);});
      await asUser(ids.studentB,async db=>{assert.equal((await db.query('SELECT * FROM app.shop_orders')).rowCount,0);assert.equal((await db.query('SELECT * FROM app.shop_order_items')).rowCount,0);});
      await asUser(ids.studentA,async db=>assert.equal((await db.query('SELECT * FROM app.shop_order_items')).rowCount,1));
      await assert.rejects(owner.query("INSERT INTO app.payments(order_id,payer_id,amount_cents,provider,request_key) VALUES($1,$2,500,'offline',$3)",[order,ids.studentB,randomUUID()]),rejected('23514'));
      const payment=(await owner.query("INSERT INTO app.payments(order_id,payer_id,amount_cents,provider,request_key,status,paid_at) VALUES($1,$2,500,'offline',$3,'succeeded',now()) RETURNING id",[order,ids.studentA,randomUUID()])).rows[0].id;
      await owner.query("INSERT INTO app.refunds(payment_id,request_key,amount_cents,reason) VALUES($1,$2,300,'test')",[payment,randomUUID()]);
      await assert.rejects(owner.query("INSERT INTO app.refunds(payment_id,request_key,amount_cents,reason) VALUES($1,$2,300,'over-refund')",[payment,randomUUID()]),rejected('23514'));
    });
    await t.test('open errand listing hides encrypted locations from unrelated users',async()=>{
      await owner.query("INSERT INTO app.errand_tasks(publisher_id,title,description,pickup_location_ciphertext,dropoff_location_ciphertext,request_key) VALUES($1,'Deliver','Private details',$2,$2,$3)",[ids.studentA,Buffer.from('private-location'),randomUUID()]);
      await asUser(ids.studentB,async db=>{
        const list=await db.query('SELECT * FROM app.errand_open_list');assert.equal(list.rowCount,1);assert.ok(!('description' in list.rows[0]));assert.ok(!('pickup_location_ciphertext' in list.rows[0]));
        assert.equal((await db.query('SELECT * FROM app.errand_tasks')).rowCount,0);
      });
      await asUser(null,async db=>assert.equal((await db.query('SELECT * FROM app.errand_open_list')).rowCount,0));
    });
    await t.test('errand assignment must match exactly one accepted offer',async()=>{
      const task=(await owner.query('SELECT id FROM app.errand_tasks LIMIT 1')).rows[0].id;
      await assert.rejects(owner.query("INSERT INTO app.errand_offers(task_id,runner_id) VALUES($1,$2)",[task,ids.studentA]),rejected('23514'));
      await owner.query('INSERT INTO app.errand_offers(task_id,runner_id) VALUES($1,$2)',[task,ids.studentB]);
      await assert.rejects(owner.query("UPDATE app.errand_tasks SET accepted_runner_id=$2,status='assigned' WHERE id=$1",[task,ids.studentB]),rejected('23514'));
      await owner.query('BEGIN');
      try {
        await owner.query("UPDATE app.errand_offers SET status='accepted' WHERE task_id=$1 AND runner_id=$2",[task,ids.studentB]);
        await owner.query("UPDATE app.errand_tasks SET accepted_runner_id=$2,status='assigned' WHERE id=$1",[task,ids.studentB]);
        await owner.query('COMMIT');
      }catch(error){await owner.query('ROLLBACK');throw error;}
      await asUser(ids.studentB,async db=>assert.equal((await db.query('SELECT * FROM app.errand_tasks')).rowCount,1));
    });
  } finally {
    for(const db of [agent,backend,owner])if(db){try{await db.query('ROLLBACK');}catch{}await db.end();}
    if(created)await control.query(`DROP DATABASE "${name}"`);
    await control.end();
  }
});
