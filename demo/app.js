const total = 1000;

let lending = 300;
let bond = 200;
let escrow = 100;

function currentLocked() {
  return lending + bond + escrow;
}

function reserveLending(amount) {
  if (currentLocked() + amount > total) {
    alert("insufficient available value");
    return;
  }

  lending += amount;
  refresh();
}

function reserveBond(amount) {
  if (currentLocked() + amount > total) {
    alert("insufficient available value");
    return;
  }

  bond += amount;
  refresh();
}

function reserveEscrow(amount) {
  if (currentLocked() + amount > total) {
    alert("insufficient available value");
    return;
  }

  escrow += amount;
  refresh();
}

function refresh() {
  const locked = currentLocked();
  const available = total - locked;

  document.getElementById("totalValue").innerText =
    `${total} ETH`;

  document.getElementById("lockedValue").innerText =
    `${locked} ETH`;

  document.getElementById("availableValue").innerText =
    `${available} ETH`;

  document.getElementById("lockedBar").style.width =
    `${(locked / total) * 100}%`;

  document.getElementById("lendingAmount").innerText =
    `${lending} ETH`;

  document.getElementById("bondAmount").innerText =
    `${bond} ETH`;

  document.getElementById("escrowAmount").innerText =
    `${escrow} ETH`;
}

window.addEventListener("load", refresh);