const total = 1000;

let lending = 300;
let bond = 200;
let escrow = 100;

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

  document.getElementById("totalValue").innerText = `${total} ETH`;
  document.getElementById("lockedValue").innerText = `${locked} ETH`;
  document.getElementById("availableValue").innerText = `${available} ETH`;

  document.getElementById("lockedBar").style.width =
    `${(locked / total) * 100}%`;

  document.getElementById("lendingAmount").innerText = `${lending} ETH`;
  document.getElementById("bondAmount").innerText = `${bond} ETH`;
  document.getElementById("escrowAmount").innerText = `${escrow} ETH`;
}

window.addEventListener("load", refresh);