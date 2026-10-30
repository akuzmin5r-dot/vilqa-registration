const fs=require('node:fs'),assert=require('node:assert/strict');
const split=require('../src/telegram.cjs').telegramChunks;
let passed=0;
for(const input of ['Обычное сообщение','<b>'+('еда 🥗 '.repeat(2000))+'</b>','<blockquote><b>'+('текст &amp; '.repeat(2000))+'</b></blockquote>','<b>несбалансированный текст','<script>alert(1)</script>','<b>текст</i></b>', '🥗'.repeat(3000)]){
 const parts=split(input);for(const part of parts){assert(part.length<=3500);const stack=[];for(const match of part.matchAll(/<(\/?)(b|i|code|blockquote)>/g)){if(match[1])assert.equal(stack.pop(),match[2]);else stack.push(match[2]);}assert.equal(stack.length,0);assert(!part.includes('<script>'));}passed++;
}
assert.equal(split('<b>рыба & мясо</b>')[0],'<b>рыба &amp; мясо</b>');passed++;
assert.equal(split('🥗'.repeat(3000)).join(''),'🥗'.repeat(3000));passed++;
console.log(JSON.stringify({passed}));
