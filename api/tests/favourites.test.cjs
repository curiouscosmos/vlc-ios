// node api/tests/favourites.test.cjs (Node 24+). No credentials or network.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { stripTypeScriptTypes } = require('node:module');
const { DatabaseSync } = require('node:sqlite');
const source = fs.readFileSync(require('node:path').join(__dirname, '../edge.ts'), 'utf8');
const start = source.indexOf('async function resolveFavourites(');
const end = source.indexOf('/**\n * Router', start);
const sqlite = new DatabaseSync(':memory:');
sqlite.exec(`CREATE TABLE discourse (id TEXT PRIMARY KEY, is_audio_cleaned INTEGER);
    CREATE TABLE discourse_audio (id TEXT PRIMARY KEY, audio_url TEXT);
    INSERT INTO discourse VALUES ('d1', 1);
    INSERT INTO discourse_audio VALUES ('a1', 'https://example.test/a.mp3');`);
let queries = 0;
const resolve = vm.runInNewContext(stripTypeScriptTypes(source.slice(start, end)) + '\nresolveFavourites', {
    Response, db: { async execute({sql, args}) { queries++; return { rows: sqlite.prepare(sql).all(...args) }; } },
    normalizeDiscourse: row => ({ ...row, is_audio_cleaned: Boolean(row.is_audio_cleaned) }),
    jsonResponse: (value, status = 200) => Response.json(value, { status })
});
const request = body => new Request('https://example.test/favourites/resolve', { method: 'POST', body: JSON.stringify(body) });
(async () => {
    for (const body of [null, [], {}, { discourse_ids: 'd1', discourse_audio_ids: [] },
        { discourse_ids: [''], discourse_audio_ids: [] }, { discourse_ids: [42], discourse_audio_ids: [] },
        { discourse_ids: [' x '], discourse_audio_ids: [] },
        { discourse_ids: ['x'.repeat(257)], discourse_audio_ids: [] },
        { discourse_ids: [], discourse_audio_ids: [], user_id: 'not-needed' },
        { discourse_ids: Array(50).fill('d1'), discourse_audio_ids: Array(51).fill('a1') },
        { discourse_ids: Array(101).fill('d1'), discourse_audio_ids: [] }]) {
        assert.equal((await resolve(request(body))).status, 400);
    }
    assert.equal((await resolve(new Request('https://example.test', {method:'POST',body:'{'}))).status, 400);
    assert.equal(queries, 0, 'Invalid requests must not query the database');
    const body = await (await resolve(request({ discourse_ids: ['d1', 'gone', "' OR 1=1 --"], discourse_audio_ids: ['a1', 'gone'] }))).json();
    assert.equal(body.discourses[0].is_audio_cleaned, true);
    assert.equal(body.audios[0].id, 'a1');
    assert.deepEqual(body.missing_discourse_ids, ['gone', "' OR 1=1 --"]);
    assert.deepEqual(body.missing_discourse_audio_ids, ['gone']);
    assert.equal(queries, 2, 'Two batched indexed lookups');
    const empty = await (await resolve(request({discourse_ids: [], discourse_audio_ids: []}))).json();
    assert.deepEqual(empty.discourses, []);
    assert.equal(queries, 2, 'Empty lists require no query');
    assert.equal((await resolve(request({discourse_ids: Array(100).fill('d1'), discourse_audio_ids: []}))).status, 200);
    sqlite.close();
    console.log('Favourites resolver: validation, batch limit, normalization, missing IDs, empty lists, SQL parameters passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
