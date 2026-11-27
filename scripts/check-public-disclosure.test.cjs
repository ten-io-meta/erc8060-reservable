"use strict";
const {test}=require("node:test");
const assert=require("node:assert/strict");
const fs=require("node:fs");
const path=require("node:path");
const vm=require("node:vm");

const root=path.resolve(__dirname,"..");
const read=p=>fs.readFileSync(path.join(root,p),"utf8");
const html=read("demo/index.html"),js=read("demo/app.js"),css=read("demo/style.css");

test("public landing state never displays fictitious ETH as recorded collateral",()=>{
  assert.match(html,/SIMULATED BALANCES — NOT REAL ETH/);
  assert.match(html,/invented demo units/);
  assert.match(html,/No ETH is deposited/);
  assert.match(html,/Strict ERC-8060 redemption:<\/strong> not implemented/);
  assert.match(html,/Independent security audit:<\/strong> not completed/);
  assert.match(html,/ERC-165 profile detection:<\/strong> not implemented/);
  assert.doesNotMatch(html,/ERC-8060 Treasury #1/);
  assert.doesNotMatch(html,/>[\d,.]+\s*ETH\s*</i);
  assert.equal((html.match(/id="(?:totalValue|lockedValue|availableValue|lendingAmount|bondAmount|escrowAmount)"/g)||[]).length,6);
  assert.match(css,/\.disclosure\s*\{/);
  assert.match(css,/\.boundaries\s*\{/);
});
test("browser interaction stays an isolated simulated holder/units counter",()=>{
  const elements=new Map();
  const alerts=[];
  const document={getElementById(id){
    if(!elements.has(id))elements.set(id,{innerText:"",style:{width:""}});
    return elements.get(id);
  }};
  let load;
  const sandbox=vm.createContext({
    document,alert:m=>alerts.push(m),
    window:{addEventListener(name,cb){assert.equal(name,"load");load=cb;}}
  });
  vm.runInContext(js,sandbox,{filename:"demo/app.js",timeout:1000});
  assert.equal(typeof load,"function");
  load();
  assert.equal(elements.get("totalValue").innerText,"1000 demo units");
  assert.equal(elements.get("lockedValue").innerText,"600 demo units");
  assert.equal(elements.get("availableValue").innerText,"400 demo units");
  vm.runInContext("reserveLending(50); transferNFT();",sandbox,{timeout:1000});
  assert.equal(elements.get("lockedValue").innerText,"650 demo units");
  assert.equal(elements.get("availableValue").innerText,"350 demo units");
  assert.equal(elements.get("ownerLabel").innerText,"Simulated holder: Bob");
  assert.match(alerts.at(-1),/Simulation only:/);
  vm.runInContext("reserveEscrow(500);",sandbox,{timeout:1000});
  assert.equal(elements.get("availableValue").innerText,"350 demo units");
  assert.match(alerts.at(-1),/insufficient available value/);
  assert.doesNotMatch(js,/\\\$\{[a-zA-Z]+\\\} ETH/);
  assert.doesNotMatch(js,/NFT ownership transferred\./);
});
test("public documentation does not certify mock ETH redemptions or final security",()=>{
  const readme=read("README.md");
  const development=read("docs/DEVELOPMENT_REPORT.md");
  const accounting=read("docs/commitment-accounting.md");
  const disclosure=read("docs/disclosure-and-indexing.md");
  const scope=read("docs/external-audit-scope-and-findings.md");
  assert.match(readme,/No wallet, no Ethereum RPC, no on-chain transactions, no actual ETH/);
  assert.match(readme,/not protocol-closed in a financial-security sense/i);
  assert.match(readme,/no executable payout or economic settlement/i);
  assert.doesNotMatch(readme,/the design is therefore considered to have reached protocol closure/i);
  assert.match(development,/no independent security audit/i);
  assert.match(accounting,/valueOf\(uint256\)/);
  assert.match(accounting,/not real collateral, ETH delivery or unconditional redemption/i);
  assert.match(disclosure,/not authenticated ETH collateral/i);
  assert.match(scope,/No external auditor has been appointed/i);
  assert.match(scope,/Release status: BLOCKED/i);
  assert.match(scope,/R-01/);
  assert.match(scope,/R-05/);
});
test("test file explicitly records unremediated risks rather than falsely asserting safety",()=>{
  const suite=read("test/ExternalAuditReproduction.test.js");
  assert.equal((suite.match(/it\("UNSAFE:/g)||[]).length,5);
  assert.match(suite,/prior owner unused allowance remains executable/i);
  assert.match(suite,/third party may mark another user's lending position closed/i);
});
