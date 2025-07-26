var Inventory = {};
var mousedown = false;
var draggedElement = null;
var contextItem = null;


/* function addNotification(message, duration = 3000) {
    const container = document.getElementById('notification-container');
    const notification = document.createElement('div');
    notification.className = 'notification';
    notification.textContent = message;

    container.appendChild(notification);

    setTimeout(() => {
        notification.classList.add('fade-out');
        setTimeout(() => {
            container.removeChild(notification);
        }, 500);
    }, duration);
} */

function hideContextMenu() {
    const contextMenu = document.getElementById('context-menu');
    contextMenu.style.display = 'none';
    contextItem = null;
}

function onMouseMove(event) {
    event.preventDefault();

    if (draggedElement) {
        draggedElement.style.left = event.pageX + 'px';
        draggedElement.style.top = event.pageY + 'px';
    }
}

function createItemSlot(slot, item, inventorytype, inventoryid) {
    let element = document.createElement('div');

    element.className = 'item-slot';
    element.setAttribute('data-slot', slot);
    element.setAttribute('inventory-id', inventoryid);

    if (item !== undefined) {
        element.setAttribute('item', JSON.stringify(item));
    }

    let itemImage = createElement('div', 'item-slot-img');
    addElement(element, itemImage);

    if (item !== undefined) {
        let itemImageItem = createElement('img');
        itemImageItem.src = "images/" + item.image;
        addElement(itemImage, itemImageItem);
    }

    let itemAmount = createElement('div', 'item-slot-amount');
    if (item !== undefined) {
        itemAmount.innerHTML = item.amount;
    }
    addElement(element, itemAmount);


    if (slot <= 5 && inventorytype == "player") {
        let slotLabelContainer = createElement('div', 'item-slot-key');
        addElement(element, slotLabelContainer);

        let slotLabel = createElement('p', 'slot-label', slot);
        addElement(slotLabelContainer, slotLabel);
    }

    return element;
}

function createElement(elementType, className, innerHTML) {
    var element = document.createElement(elementType);

    if (className !== undefined) {
        element.className = className;
    }

    if (innerHTML !== undefined) {
        element.innerHTML = innerHTML;
    }

    return element;
}

function addElement(parentElement, childElement) {
    // Verifica si los argumentos son elementos válidos
    if (parentElement instanceof HTMLElement && childElement instanceof HTMLElement) {
        parentElement.appendChild(childElement);
    } else {
        console.error('Los argumentos deben ser elementos HTML válidos');
    }
}

Inventory.Open = (data) => {

    Inventory.id = data.id;
    Inventory.type = data.type;
    Inventory.slots = data.slots;
    Inventory.items = Object.values(data.inventory);
    Inventory.weight = data.weight;
    Inventory.maxWeight = data.maxweight;
    Inventory.other = data.other;

    var mainInventory = document.querySelector('.player-inventory');
    var mainInventoryLabel = document.querySelector('#player-inv-label');
    var otherInventoryLabel = document.querySelector('#other-inv-label');
    var mainInventoryWeight = document.querySelector('#player-inv-weight-value');

    mainInventoryLabel.innerHTML = Inventory.id;
    otherInventoryLabel.innerHTML = Inventory.other !== undefined ? Inventory.other.id : "Suelo";
    mainInventoryWeight.innerHTML = `${Inventory.weight / 1000} kg / ${Inventory.maxWeight/1000} kg`;
    mainInventory.innerHTML = '';

    for (let i = 1; i <= Inventory.slots; i++) {
        const slotItem = Inventory.items.find(item => item !== null && item.slot === i);
        var slot = createItemSlot(i, slotItem, "player", Inventory.id);
        addElement(mainInventory, slot);
    }

    var otherInventory = document.querySelector('.other-inventory');
    otherInventory.innerHTML = '';

    Inventory.other = Inventory.other !== undefined ? Inventory.other : {};
    Inventory.other.id = Inventory.other.id !== undefined ? Inventory.other.id : 0;
    Inventory.other.slots = Inventory.other.slots !== undefined ? Inventory.other.slots : 25;
    Inventory.other.items = Inventory.other.items !== undefined ? Object.values(Inventory.other.items) : [];

    for (let j = 1; j < Inventory.other.slots; j++) {
        const otherSlot = Inventory.other.items.find(item => item != null && item.slot === j);
        var slot = createItemSlot(j, otherSlot, "other", Inventory.other.id);
        addElement(document.querySelector('.other-inventory'), slot);
    }

}

Inventory.Close = () => {
    $("#qbcore-inventory").fadeOut(300);
    const contextMenu = document.getElementById('context-menu');
    var notificationElement = document.getElementById('item-info');
    notificationElement.style.display = 'none';
    contextMenu.style.display = 'none';
    $.post("https://qb-inventory/CloseInventory", JSON.stringify({}));
}

document.addEventListener('mouseover', function (event) {
    var closest = event.target.closest('.item-slot');
    var notificationElement = document.getElementById('item-info');

    if (closest == null) { notificationElement.style.display = 'none'; return; }

    var hasItem = JSON.parse(closest.getAttribute('item'));


    if (hasItem != null) {
        notificationElement.style.display = 'block';

        switch (hasItem.type) {
            case "weapon":
                notificationElement.innerHTML = `Name 〣 ${hasItem.label}<br> 
                        Serial 〣 ${hasItem.info.serie == undefined ? "Unknown" : hasItem.info.serie} <br> 
                        Quantity 〣 x${hasItem.amount} <br> 
                        Ammo 〣 ${hasItem.info.ammo == undefined ? "Unloaded" : hasItem.info.ammo} <br> `;
                break;
            default:
                notificationElement.innerHTML = `${hasItem.label} 〣 x${hasItem.amount}`;

                if (hasItem.info != undefined) {
                    var info = Object.entries(hasItem.info).map(([key, value]) => `${key} 〣 ${value}`).join('<br>');
                    notificationElement.innerHTML += `<br>${info}`;
                }

                break;
        }

    }

});

document.addEventListener('mousedown', function (event) {
    mousedown = true;
    
    if (event.buttons != 1) { return; } // Solo permite el click izquierdo para drag

    const slot_element = event.target.closest('.item-slot');

    if (slot_element != undefined && slot_element.className == "item-slot") {
        const item = slot_element.getAttribute('item');

        if (item == null || item == undefined) {
            console.error("No item found");
            return;
        } else {
            // Clonar el elemento
            draggedElement = slot_element.cloneNode(true);

            draggedElement.style.opacity = '0.5';
            draggedElement.style.position = 'absolute';
            draggedElement.style.pointerEvents = 'none';

            document.body.appendChild(draggedElement);
        }
        document.addEventListener('mousemove', onMouseMove);
    }

});

document.addEventListener('mouseup', function (event) {
    mousedown = false;

    /* Mirar aqui , hay slots que fuman porritos */

    if (draggedElement != null) {

        const target = event.target.closest('.item-slot');

        if (draggedElement != null && target != null && target.className == "item-slot") {

            const draggedItem = JSON.parse(draggedElement.getAttribute('item'));
            const fromInventory = draggedElement.getAttribute('inventory-id');
            const fromSlot = draggedElement.getAttribute('data-slot');

            var targetItem = JSON.parse(target.getAttribute('item'));

            var toInventory = target.getAttribute('inventory-id');
            const toSlot = target.getAttribute('data-slot');

            if (!toInventory) {
                toInventory = fromInventory;
            }

            if (toSlot != fromSlot || toInventory != fromInventory) {
                $.post("https://qb-inventory/SetInventoryData", JSON.stringify({
                    fromInventory: fromInventory,
                    toInventory: toInventory,
                    fromSlot: fromSlot,
                    toSlot: toSlot,
                    fromAmount: draggedItem.amount !== undefined ? draggedItem.amount : 1,
                    toAmount: targetItem !== null ? targetItem.amount : 1
                }));
            }
        }

        document.body.removeChild(draggedElement);
        draggedElement = null;

        document.removeEventListener('mousemove', onMouseMove);
    }
});

window.addEventListener('contextmenu', function (event) {
    event.preventDefault();
    const target = event.target.closest('.item-slot');
    var contextRange = document.getElementsByClassName("context-amount")[0];

    if (target == null) {
        hideContextMenu();
        return;
    }

    const item = JSON.parse(target.getAttribute('item'));

    if (item == null) {
        hideContextMenu();
        return;
    }

    contextRange.value = 1;
    contextRange.nextElementSibling.value = 1;
    contextRange.max = parseInt(item.amount);
    contextRange.min = 1;

    const contextMenu = document.getElementById('context-menu');
    contextMenu.style.display = 'block';

    if (event.pageX + contextMenu.offsetWidth > window.innerWidth) {
        contextMenu.style.left = `${event.pageX - contextMenu.offsetWidth}px`;
    } else {
        contextMenu.style.left = `${event.pageX}px`;
    }

    contextMenu.style.top = `${event.pageY}px`;


    contextItem = item;

    if (item.type != "item_weapon") {
        document.getElementById('context-attachments').style.display = 'none';
    }

    contextItem.amount = item.amount !== undefined ? item.amount : 1;

    // Context menu actions
    document.getElementById('context-use').onclick = function () {
        $.post("https://qb-inventory/UseItem", JSON.stringify({
            inventory: target.getAttribute('inventory-id'),
            item: contextItem,
        }));
        hideContextMenu();
    }

    contextRange = document.getElementsByClassName("context-amount")[0];

    document.getElementById("context-give").onclick = function () {
        $.post(
            "https://qb-inventory/GiveItem",
            JSON.stringify({
                inventory: target.getAttribute("inventory-id"),
                item: contextItem,
                amount: parseInt(contextRange.value),
            })
        );
        hideContextMenu();
    }

    this.document.getElementById("context-split").onclick = function () {
        $.post("https://qb-inventory/SetInventoryData", JSON.stringify({
            fromInventory: target.getAttribute("inventory-id"),
            toInventory: target.getAttribute("inventory-id"),
            fromSlot: contextItem.slot,
            fromAmount: parseInt(contextRange.value)
        }));
        hideContextMenu();
    }

});

window.addEventListener('keydown', function (event) {

    if (event.repeat) {
        return;
    }

    switch (event.keyCode) {
        case 27: // ESC
            Inventory.Close();
            break;
        case 9: // TAB
            Inventory.Close();
            break;
    }

});

window.addEventListener('message', (event) => {

    var action = event.data.action;
    var data = event.data;

    switch (action) {
        case "open":
            $("#qbcore-inventory").fadeIn(300);
            Inventory.Open(data);
            break;
        case "update":
            Inventory.Open(data);
            break;
        case "close":
            Inventory.Close();
            break;
    }
})