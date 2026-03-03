const app = document.getElementById('app');
const stationTitle = document.getElementById('stationTitle');
const recipeList = document.getElementById('recipeList');
const closeBtn = document.getElementById('closeBtn');
const recipeTemplate = document.getElementById('recipeTemplate');

let currentPayload = null;

const post = (name, data = {}) => {
  fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  }).catch(() => {});
};

const clearRecipes = () => {
  while (recipeList.firstChild) recipeList.removeChild(recipeList.firstChild);
};

const createListItems = (arr, formatter) => {
  return (arr || []).map((x) => {
    const li = document.createElement('li');
    li.textContent = formatter(x);
    return li;
  });
};

const renderRecipe = (stationId, recipe) => {
  const node = recipeTemplate.content.firstElementChild.cloneNode(true);

  node.querySelector('.recipe-name').textContent = recipe.label || recipe.id;
  node.querySelector('.recipe-time').textContent = `${recipe.duration || 0}ms`;
  node.querySelector('.recipe-description').textContent = recipe.description || '';

  const ingredientsEl = node.querySelector('.ingredients');
  const outputsEl = node.querySelector('.outputs');

  createListItems(recipe.ingredients, (i) => `${i.item} x${i.amount}`).forEach((li) => ingredientsEl.appendChild(li));
  createListItems(recipe.outputs, (o) => `${o.item} x${o.amount} (${o.chance ?? 100}%)`).forEach((li) => outputsEl.appendChild(li));

  const status = node.querySelector('.status');
  const buttons = node.querySelectorAll('.craft-btn');

  buttons.forEach((btn) => {
    const qty = btn.dataset.qty;
    const canMultiple = recipe.canCraftMultiple === true;

    if ((qty === '5' || qty === '10') && !canMultiple) {
      btn.disabled = true;
    }

    const avail = recipe.availability?.[qty];
    if (avail && avail.canCraft === false) {
      btn.disabled = true;
      status.textContent = avail.reason || 'Missing requirements.';
      status.classList.add('fail');
    }

    btn.addEventListener('click', () => {
      post('craftRequest', {
        stationId,
        recipeId: recipe.id,
        quantity: Number(qty),
      });
    });
  });

  return node;
};

const openCraft = (payload) => {
  currentPayload = payload;
  stationTitle.textContent = payload?.station?.title || payload?.station?.label || 'Crafting';
  clearRecipes();

  (payload?.recipes || []).forEach((recipe) => {
    recipeList.appendChild(renderRecipe(payload.station.id, recipe));
  });

  app.classList.remove('hidden');
};

const closeUi = () => {
  app.classList.add('hidden');
  currentPayload = null;
  post('close');
};

window.addEventListener('message', (event) => {
  const data = event.data;
  if (!data || !data.action) return;

  if (data.action === 'setVisible') {
    if (data.visible) app.classList.remove('hidden');
    else app.classList.add('hidden');
  }

  if (data.action === 'openCraft') {
    openCraft(data.payload);
  }
});

window.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') closeUi();
});

closeBtn.addEventListener('click', closeUi);
