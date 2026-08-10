import './styles.css';
import { signInWithGoogle, signOutUser, watchAuthState } from './auth.js';
import { getActivePlans, groupPlansByCategory } from './plans.js';
import { applyCoupon, purchasePlan, validateCoupon } from './checkout.js';

const app = document.getElementById('app');

let currentUser = null;
let plans = [];

watchAuthState(async (user) => {
  currentUser = user;
  if (user) {
    plans = await getActivePlans();
  }
  render();
});

render();

function render() {
  app.innerHTML = '';
  if (!currentUser) {
    app.appendChild(renderSignIn());
    return;
  }
  app.appendChild(renderHeader());
  app.appendChild(renderPlanList());
}

function renderSignIn() {
  const wrap = document.createElement('div');
  wrap.innerHTML = `
    <h2>PSAS Memberships</h2>
    <p class="subtitle">Sign in to browse and buy a membership plan.</p>
  `;
  const btn = document.createElement('button');
  btn.className = 'btn-primary';
  btn.textContent = 'Sign in with Google';
  btn.onclick = async () => {
    btn.disabled = true;
    try {
      await signInWithGoogle();
    } catch (err) {
      showError(wrap, err.message ?? String(err));
    } finally {
      btn.disabled = false;
    }
  };
  wrap.appendChild(btn);
  return wrap;
}

function renderHeader() {
  const header = document.createElement('div');
  header.style.display = 'flex';
  header.style.justifyContent = 'space-between';
  header.style.alignItems = 'center';
  header.style.marginBottom = '12px';

  const name = document.createElement('span');
  name.textContent = currentUser.displayName ?? currentUser.email ?? '';

  const signOutBtn = document.createElement('button');
  signOutBtn.className = 'btn-secondary';
  signOutBtn.textContent = 'Sign out';
  signOutBtn.onclick = () => signOutUser();

  header.appendChild(name);
  header.appendChild(signOutBtn);
  return header;
}

function renderPlanList() {
  const wrap = document.createElement('div');
  const groups = groupPlansByCategory(plans);
  if (groups.size === 0) {
    wrap.innerHTML = '<p>No membership plans available right now.</p>';
    return wrap;
  }
  for (const [category, categoryPlans] of groups) {
    const heading = document.createElement('div');
    heading.className = 'category-heading';
    heading.textContent = category;
    wrap.appendChild(heading);

    for (const plan of categoryPlans) {
      wrap.appendChild(renderPlanCard(plan));
    }
  }
  return wrap;
}

function renderPlanCard(plan) {
  const card = document.createElement('div');
  card.className = 'plan-card';
  card.innerHTML = `
    <h3>${plan.name}</h3>
    <div class="subtitle">${plan.subtitle ?? ''}</div>
    <div class="price">${plan.priceLabel ?? `S$${plan.price.toFixed(2)}`}</div>
  `;
  const buyBtn = document.createElement('button');
  buyBtn.className = 'btn-primary';
  buyBtn.textContent = 'Buy';
  buyBtn.style.marginTop = '8px';
  buyBtn.onclick = () => openCheckout(plan);
  card.appendChild(buyBtn);
  return card;
}

function openCheckout(plan) {
  const backdrop = document.createElement('div');
  backdrop.className = 'modal-backdrop';
  backdrop.onclick = (e) => {
    if (e.target === backdrop) backdrop.remove();
  };

  const sheet = document.createElement('div');
  sheet.className = 'modal-sheet';
  sheet.innerHTML = `
    <h3>${plan.name}</h3>
    <div id="checkout-amount" class="price">S$${plan.price.toFixed(2)}</div>
    <input class="field" id="coupon-input" placeholder="Coupon code (optional)" />
    <button class="btn-secondary" id="apply-coupon-btn">Apply coupon</button>
    <div id="coupon-message"></div>
    <div id="payment-element"></div>
    <button class="btn-primary" id="confirm-purchase-btn" style="width:100%;margin-top:12px;">Confirm purchase</button>
    <div id="purchase-message"></div>
  `;
  backdrop.appendChild(sheet);
  app.appendChild(backdrop);

  let appliedCoupon = null;
  let finalAmount = plan.price;
  const amountEl = sheet.querySelector('#checkout-amount');
  const couponMsg = sheet.querySelector('#coupon-message');
  const purchaseMsg = sheet.querySelector('#purchase-message');
  const paymentContainer = sheet.querySelector('#payment-element');

  sheet.querySelector('#apply-coupon-btn').onclick = async () => {
    const code = sheet.querySelector('#coupon-input').value.trim();
    if (!code) return;
    try {
      appliedCoupon = await validateCoupon(code);
      finalAmount = applyCoupon(appliedCoupon, plan.price);
      amountEl.textContent = `S$${finalAmount.toFixed(2)}`;
      showSuccess(couponMsg, 'Coupon applied');
    } catch (err) {
      showError(couponMsg, err.message ?? String(err));
    }
  };

  sheet.querySelector('#confirm-purchase-btn').onclick = async (e) => {
    const btn = e.currentTarget;
    btn.disabled = true;
    try {
      await purchasePlan({
        plan,
        coupon: appliedCoupon,
        finalAmount,
        paymentContainer,
      });
      showSuccess(
        purchaseMsg,
        `${plan.name} activated! +${plan.credits} credits added.`
      );
      plans = await getActivePlans();
      setTimeout(() => {
        backdrop.remove();
        render();
      }, 1500);
    } catch (err) {
      showError(purchaseMsg, err.message ?? String(err));
    } finally {
      btn.disabled = false;
    }
  };
}

function showError(container, message) {
  const el = document.createElement('p');
  el.className = 'error-text';
  el.textContent = message;
  container.appendChild(el);
}

function showSuccess(container, message) {
  const el = document.createElement('p');
  el.className = 'success-text';
  el.textContent = message;
  container.appendChild(el);
}
