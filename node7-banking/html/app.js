const bankRoot = document.getElementById('bank');
const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'node7-banking';

const state = {
    data: null,
    selectedShared: '',
    activeTab: 'cashier',
    busy: false,
};

const money = (value) => new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
}).format(Number(value || 0));

const gold = (value) => Number(value || 0).toLocaleString('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
});

const escapeHtml = (value) => String(value ?? '').replace(/[&<>'"]/g, (char) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    "'": '&#39;',
    '"': '&quot;',
}[char]));

function setStatus(text, isError = false) {
    const element = document.getElementById('statusText');
    element.textContent = text || 'Secure NODE7 banking connection';
    element.style.color = isError ? 'var(--red)' : '';
}

async function post(endpoint, payload = {}) {
    try {
        const response = await fetch(`https://${resourceName}/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(payload),
        });
        return await response.json();
    } catch (error) {
        setStatus('Banking connection failed. Please try again.', true);
        return { success: false, message: 'Banking connection failed.' };
    }
}

function setBusy(busy) {
    state.busy = busy;
    document.querySelectorAll('form button, form input, #refreshButton, .remove-member').forEach((element) => {
        element.disabled = busy;
    });
    document.querySelectorAll('.section-button, .account-edition, #closeButton').forEach((element) => {
        element.disabled = false;
    });
    if (busy) {
        setStatus('Processing official banking record…');
    } else if (state.data?.sharedAccount) {
        applySharedPermissions(state.data.sharedAccount);
    }
}

function setActiveTab(tabName) {
    state.activeTab = tabName;
    document.querySelectorAll('.section-button').forEach((button) => {
        button.classList.toggle('active', button.dataset.tab === tabName);
    });
    document.querySelectorAll('.page-section').forEach((section) => {
        section.classList.toggle('active', section.id === tabName);
    });
}

function permissionText(permissions) {
    const items = [];
    if (permissions.deposit) items.push('Deposit');
    if (permissions.withdraw) items.push('Withdraw');
    if (permissions.transfer) items.push('Transfer');
    if (permissions.manage) items.push('Manage');
    return items.length ? items.join(' · ') : 'View only';
}

function renderPersonalHistory(entries) {
    const body = document.getElementById('historyBody');
    if (!Array.isArray(entries) || !entries.length) {
        body.innerHTML = '<tr><td colspan="5" class="empty">No personal account entries have been recorded.</td></tr>';
        return;
    }

    body.innerHTML = entries.map((entry) => {
        const amount = Number(entry.amount || 0);
        const positive = amount >= 0;
        const date = entry.createdAt ? new Date(entry.createdAt).toLocaleString('en-US') : '—';
        const details = [
            escapeHtml(entry.description || 'Bank transaction'),
            entry.counterparty ? `Counterparty: ${escapeHtml(entry.counterparty)}` : '',
            entry.reference ? `Reference: ${escapeHtml(entry.reference)}` : '',
        ].filter(Boolean).join('<br>');

        return `<tr>
            <td>${escapeHtml(String(entry.type || '').replaceAll('_', ' '))}</td>
            <td>${details}</td>
            <td class="amount ${positive ? 'positive' : 'negative'}">${positive ? '+' : ''}${money(amount)}</td>
            <td class="amount">${money(entry.balanceAfter)}</td>
            <td>${date}</td>
        </tr>`;
    }).join('');
}

function renderSharedHistory(entries) {
    const body = document.getElementById('sharedHistoryBody');
    if (!Array.isArray(entries) || !entries.length) {
        body.innerHTML = '<tr><td colspan="6" class="empty">No company-account entries have been recorded.</td></tr>';
        return;
    }

    body.innerHTML = entries.map((entry) => {
        const amount = Number(entry.amount || 0);
        const positive = amount >= 0;
        const date = entry.createdAt ? new Date(entry.createdAt).toLocaleString('en-US') : '—';
        const details = [
            escapeHtml(entry.description || 'Account activity'),
            entry.counterparty ? `Counterparty: ${escapeHtml(entry.counterparty)}` : '',
            entry.reference ? `Reference: ${escapeHtml(entry.reference)}` : '',
        ].filter(Boolean).join('<br>');

        return `<tr>
            <td>${escapeHtml(String(entry.type || '').replaceAll('_', ' '))}</td>
            <td>${details}</td>
            <td>${escapeHtml(entry.actorName || 'System')}</td>
            <td class="amount ${positive ? 'positive' : 'negative'}">${positive ? '+' : ''}${money(amount)}</td>
            <td class="amount">${money(entry.balanceAfter)}</td>
            <td>${date}</td>
        </tr>`;
    }).join('');
}

function renderMembers(members) {
    const body = document.getElementById('memberBody');
    if (!Array.isArray(members) || !members.length) {
        body.innerHTML = '<tr><td colspan="4" class="empty">No managed members are listed.</td></tr>';
        return;
    }

    body.innerHTML = members.map((member) => {
        const access = permissionText({
            deposit: Number(member.canDeposit) === 1 || member.canDeposit === true,
            withdraw: Number(member.canWithdraw) === 1 || member.canWithdraw === true,
            transfer: Number(member.canTransfer) === 1 || member.canTransfer === true,
            manage: Number(member.canManage) === 1 || member.canManage === true,
        });
        const removable = member.role !== 'owner';

        return `<tr>
            <td>${escapeHtml(member.memberName || member.citizenid)}</td>
            <td>${escapeHtml(member.role || 'member')}</td>
            <td>${escapeHtml(access)}</td>
            <td>${removable ? `<button class="remove-member" type="button" data-citizenid="${escapeHtml(member.citizenid)}">Remove</button>` : 'Owner'}</td>
        </tr>`;
    }).join('');
}

function renderSharedList(accounts) {
    const container = document.getElementById('sharedAccountList');
    const empty = document.getElementById('sharedRailEmpty');
    const list = Array.isArray(accounts) ? accounts : [];

    if (!list.length) {
        container.innerHTML = '';
        empty.classList.remove('hidden');
        state.selectedShared = '';
        return;
    }

    empty.classList.add('hidden');
    if (!state.selectedShared || !list.some((account) => account.name === state.selectedShared)) {
        state.selectedShared = list[0].name;
    }

    container.innerHTML = list.map((account) => `
        <button class="account-edition ${account.name === state.selectedShared ? 'active' : ''} ${account.frozen ? 'frozen' : ''}"
                type="button" data-account="${escapeHtml(account.name)}">
            <strong>${escapeHtml(account.label || account.name)}</strong>
            <span class="account-role">${escapeHtml(account.role || 'member')}</span>
            <span class="account-number">${escapeHtml(account.accountNumber || account.name)}</span>
            <span class="account-value">${money(account.balance)}</span>
        </button>
    `).join('');
}

function applySharedPermissions(account) {
    const permissions = account.permissions || {};
    const depositDisabled = !permissions.deposit || state.busy;
    const withdrawDisabled = !permissions.withdraw || account.frozen || state.busy;
    const transferDisabled = !permissions.transfer || account.frozen || state.busy;

    document.getElementById('sharedDepositForm').classList.toggle('disabled-card', !permissions.deposit);
    document.getElementById('sharedWithdrawForm').classList.toggle('disabled-card', !permissions.withdraw || account.frozen);
    document.getElementById('sharedTransferForm').classList.toggle('disabled-card', !permissions.transfer || account.frozen);

    document.querySelectorAll('#sharedDepositForm input, #sharedDepositForm button').forEach((element) => { element.disabled = depositDisabled; });
    document.querySelectorAll('#sharedWithdrawForm input, #sharedWithdrawForm button').forEach((element) => { element.disabled = withdrawDisabled; });
    document.querySelectorAll('#sharedTransferForm input, #sharedTransferForm button').forEach((element) => { element.disabled = transferDisabled; });

    document.getElementById('accountManagement').classList.toggle('hidden', !permissions.manage);
}

function renderSharedAccount(account) {
    const workspace = document.getElementById('sharedWorkspace');
    const empty = document.getElementById('sharedEmpty');

    if (!account) {
        workspace.classList.add('hidden');
        empty.classList.remove('hidden');
        document.getElementById('sharedPageTitle').textContent = 'Select an Account Edition';
        document.getElementById('sharedTypeMark').textContent = 'COMPANY DESK';
        return;
    }

    state.selectedShared = account.name;
    document.querySelectorAll('.account-edition').forEach((button) => {
        button.classList.toggle('active', button.dataset.account === account.name);
    });

    empty.classList.add('hidden');
    workspace.classList.remove('hidden');
    document.getElementById('sharedPageTitle').textContent = account.label || account.name;
    document.getElementById('sharedTypeMark').textContent = String(account.type || 'shared').replaceAll('_', ' ').toUpperCase();
    document.getElementById('sharedLabel').textContent = account.label || account.name;
    document.getElementById('sharedNumber').textContent = account.accountNumber || account.name;
    document.getElementById('sharedRole').textContent = account.role || 'member';
    document.getElementById('sharedBalance').textContent = money(account.balance);
    document.getElementById('sharedFrozen').classList.toggle('hidden', !account.frozen);

    applySharedPermissions(account);
    renderMembers(account.members || []);
    renderSharedHistory(account.history || []);
}

function render(data) {
    if (!data) return;
    state.data = data;

    const accountNumber = data.accountNumber || '—';
    document.getElementById('characterName').textContent = data.characterName || '—';
    document.getElementById('accountNumber').textContent = accountNumber;
    document.getElementById('cashierAccount').textContent = accountNumber;
    document.getElementById('cashBalance').textContent = money(data.cash);
    document.getElementById('bankBalance').textContent = money(data.bank);
    document.getElementById('goldBalance').textContent = gold(data.gold);

    renderPersonalHistory(data.history || []);
    renderSharedList(data.sharedAccounts || []);

    const creation = data.sharedCreation || {};
    const createForm = document.getElementById('createSharedForm');
    createForm.classList.toggle('hidden', !creation.enabled);
    document.getElementById('creationDetails').textContent = creation.enabled
        ? `Opening fee: ${money(creation.fee)} · Maximum personally owned accounts: ${creation.maximum}`
        : 'Private shared-account creation is disabled.';

    if (data.sharedAccount) {
        renderSharedAccount(data.sharedAccount);
    } else if (!(data.sharedAccounts || []).length) {
        renderSharedAccount(null);
    }

    setStatus('Secure NODE7 banking connection');
}

async function loadShared(accountName) {
    if (!accountName || state.busy) {
        renderSharedAccount(null);
        return;
    }

    state.selectedShared = accountName;
    document.querySelectorAll('.account-edition').forEach((button) => {
        button.classList.toggle('active', button.dataset.account === accountName);
    });

    setBusy(true);
    try {
        const response = await post('sharedAccount', { account: accountName });
        if (response && response.success && response.data) {
            state.data = {
                ...(state.data || {}),
                sharedAccounts: response.data.sharedAccounts || state.data?.sharedAccounts || [],
                sharedAccount: response.data.sharedAccount || null,
            };
            if (response.data.sharedAccounts) renderSharedList(response.data.sharedAccounts);
            renderSharedAccount(response.data.sharedAccount);
            setStatus('Company account loaded successfully.');
        } else {
            setStatus(response?.message || 'Unable to open company account.', true);
        }
    } finally {
        setBusy(false);
    }
}

function open(message) {
    const branch = message.bankName || 'Bank Office';
    document.getElementById('bankName').textContent = branch;
    document.getElementById('cashierBranch').textContent = branch;
    render(message.data);
    setActiveTab('cashier');
    bankRoot.classList.remove('hidden');
    bankRoot.setAttribute('aria-hidden', 'false');

    if (state.selectedShared && !message.data.sharedAccount) {
        loadShared(state.selectedShared);
    }
}

function close() {
    bankRoot.classList.add('hidden');
    bankRoot.setAttribute('aria-hidden', 'true');
    state.data = null;
    state.selectedShared = '';
    state.activeTab = 'cashier';
}

window.addEventListener('message', (event) => {
    const message = event.data || {};
    if (message.action === 'open') open(message);
    if (message.action === 'close') close();
    if (message.action === 'refresh') {
        render(message.data);
        if (state.selectedShared && !message.data.sharedAccount && state.activeTab === 'shared') {
            loadShared(state.selectedShared);
        }
    }
});

document.querySelectorAll('.section-button').forEach((button) => {
    button.addEventListener('click', () => {
        setActiveTab(button.dataset.tab);
        if (button.dataset.tab === 'shared' && state.selectedShared) {
            loadShared(state.selectedShared);
        }
    });
});

document.getElementById('sharedAccountList').addEventListener('click', (event) => {
    const button = event.target.closest('.account-edition');
    if (!button || state.busy) return;
    setActiveTab('shared');
    loadShared(button.dataset.account);
});

document.getElementById('closeButton').addEventListener('click', async () => {
    await post('close');
    close();
});

document.addEventListener('keydown', async (event) => {
    if (event.key === 'Escape' && !bankRoot.classList.contains('hidden')) {
        await post('close');
        close();
    }
});

async function submit(form, endpoint, payloadBuilder, successStatus) {
    if (state.busy) return;
    setBusy(true);
    try {
        const response = await post(endpoint, payloadBuilder(new FormData(form)));
        if (response && response.data) render(response.data);
        if (response && response.success) {
            form.reset();
            setStatus(successStatus || response.message || 'Transaction completed.');
            if (state.activeTab === 'shared' && state.selectedShared && !response.data?.sharedAccount) {
                await loadShared(state.selectedShared);
            }
        } else {
            setStatus(response?.message || 'The transaction could not be completed.', true);
        }
    } finally {
        setBusy(false);
    }
}

document.getElementById('depositForm').addEventListener('submit', (event) => {
    event.preventDefault();
    submit(event.currentTarget, 'deposit', (data) => ({ amount: data.get('amount') }), 'Deposit entered into the personal ledger.');
});

document.getElementById('withdrawForm').addEventListener('submit', (event) => {
    event.preventDefault();
    submit(event.currentTarget, 'withdraw', (data) => ({ amount: data.get('amount') }), 'Withdrawal entered into the personal ledger.');
});

document.getElementById('transferForm').addEventListener('submit', (event) => {
    event.preventDefault();
    submit(event.currentTarget, 'transfer', (data) => ({
        account: data.get('account'),
        amount: data.get('amount'),
        note: data.get('note'),
    }), 'Wire transfer completed.');
});

document.getElementById('createSharedForm').addEventListener('submit', (event) => {
    event.preventDefault();
    submit(event.currentTarget, 'createSharedAccount', (data) => ({ label: data.get('label') }), 'New company book opened.');
});

document.getElementById('sharedDepositForm').addEventListener('submit', (event) => {
    event.preventDefault();
    submit(event.currentTarget, 'sharedDeposit', (data) => ({
        account: state.selectedShared,
        amount: data.get('amount'),
        note: data.get('note'),
    }), 'Company deposit recorded.');
});

document.getElementById('sharedWithdrawForm').addEventListener('submit', (event) => {
    event.preventDefault();
    submit(event.currentTarget, 'sharedWithdraw', (data) => ({
        account: state.selectedShared,
        amount: data.get('amount'),
        note: data.get('note'),
    }), 'Company withdrawal recorded.');
});

document.getElementById('sharedTransferForm').addEventListener('submit', (event) => {
    event.preventDefault();
    submit(event.currentTarget, 'sharedTransfer', (data) => ({
        account: state.selectedShared,
        target: data.get('target'),
        amount: data.get('amount'),
        note: data.get('note'),
    }), 'Company transfer recorded.');
});

document.getElementById('memberForm').addEventListener('submit', (event) => {
    event.preventDefault();
    submit(event.currentTarget, 'setSharedMember', (data) => ({
        account: state.selectedShared,
        memberAccount: data.get('memberAccount'),
        role: data.get('role'),
    }), 'Member authority updated.');
});

document.getElementById('renameSharedForm').addEventListener('submit', (event) => {
    event.preventDefault();
    submit(event.currentTarget, 'renameSharedAccount', (data) => ({
        account: state.selectedShared,
        label: data.get('label'),
    }), 'Company account title updated.');
});

document.getElementById('memberBody').addEventListener('click', async (event) => {
    const button = event.target.closest('.remove-member');
    if (!button || state.busy) return;

    setBusy(true);
    try {
        const response = await post('removeSharedMember', {
            account: state.selectedShared,
            citizenid: button.dataset.citizenid,
        });
        if (response && response.data) render(response.data);
        setStatus(response?.success ? 'Member removed from the company book.' : (response?.message || 'Unable to remove member.'), !response?.success);
    } finally {
        setBusy(false);
    }
});

document.getElementById('refreshButton').addEventListener('click', async () => {
    if (state.busy) return;
    setBusy(true);
    try {
        const response = await post('refresh');
        if (response && response.data) render(response.data);
        setStatus(response?.success ? 'Personal ledger refreshed.' : 'Unable to refresh the ledger.', !response?.success);
    } finally {
        setBusy(false);
    }
});
