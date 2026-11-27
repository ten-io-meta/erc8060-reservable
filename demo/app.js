const total = 1000;

let lending = 300;
let bond = 200;
let escrow = 100;
let owner = "Alice";

function currentLocked() {
  return lending + bond + escrow;
}

function canReserve(amount) {
  return currentLocked() + amount <= total;
}

function reserveLending(amount) {
  if (!canReserve(amount)) {
    alert("insufficient available value");
    return;
  }

  lending += amount;
  refresh();
}

function reserveBond(amount) {
  if (!canReserve(amount)) {
    alert("insufficient available value");
    return;
  }

  bond += amount;
  refresh();
}

function reserveEscrow(amount) {
  if (!canReserve(amount)) {
    alert("insufficient available value");
    return;
  }

  escrow += amount;
  refresh();
}

function releaseLending(amount) {
  if (lending < amount) {
    alert("release exceeds locked value");
    return;
  }

  lending -= amount;
  refresh();
}

function releaseBond(amount) {
  if (bond < amount) {
    alert("release exceeds locked value");
    return;
  }

  bond -= amount;
  refresh();
}

function releaseEscrow(amount) {
  if (escrow < amount) {
    alert("release exceeds locked value");
    return;
  }

  escrow -= amount;
  refresh();
}

function refresh() {
  const locked = currentLocked();
  const available = total - locked;

  document.getElementById("totalValue").innerText = `${total} demo units`;
  document.getElementById("lockedValue").innerText = `${locked} demo units`;
  document.getElementById("availableValue").innerText = `${available} demo units`;

  document.getElementById("lockedBar").style.width =
    `${(locked / total) * 100}%`;

  document.getElementById("lendingAmount").innerText = `${lending} demo units`;
  document.getElementById("bondAmount").innerText = `${bond} demo units`;
  document.getElementById("escrowAmount").innerText = `${escrow} demo units`;
  document.getElementById("ownerLabel").innerText =
  `Simulated holder: ${owner}`;
}
function transferNFT() {

  if (owner === "Alice") {
    owner = "Bob";
  } else {
    owner = "Alice";
  }

  refresh();

  alert(
    "Simulation only: the displayed holder changed in your browser. The synthetic commitments stayed with this record. No NFT was transferred on-chain."
  );
}
window.addEventListener("load", refresh);