---Adds a transaction to the wallet app and sends a notification
---@param phoneNumber string
---@param amount number
---@param title string
---@param logo? string
function AddTransaction(phoneNumber, amount, title, logo)
    if not phoneNumber or not amount or not title then
        return
    end

    if #title > 50 then
        title = title:sub(1, 47) .. "..."
    end

    MySQL.insert.await("INSERT INTO phone_wallet_transactions (phone_number, amount, company, logo) VALUES (@phoneNumber, @amount, @company, @logo)", {
        phoneNumber = phoneNumber,
        amount = amount,
        company = title,
        logo = logo
    })

    local source = GetSourceFromNumber(phoneNumber)
    local content = (amount < 0 and "-" or "") .. Config.CurrencyFormat:format(SeperateNumber(math.abs(amount)))

    SendNotification(phoneNumber, {
        app = "Wallet",
        title = title,
        content = content,
        thumbnail = logo
    })

    TriggerEvent("lb-phone:onAddTransaction", amount > 0 and "received" or "paid", phoneNumber, amount, title, logo)

    Log("Wallet", source or nil, amount > 0 and "success" or "error", L("BACKEND.LOGS." .. (amount > 0 and "RECEIVED" or "PAID") .. "_TITLE", { amount = math.abs(amount) }), L("BACKEND.LOGS.TRANSACTION", {
        number = FormatNumber(phoneNumber),
        amount = amount,
        company = title
    }), logo)

    if not source then
        return
    end

    TriggerClientEvent("phone:wallet:addTransaction", source, {
        amount = amount,
        company = title,
        logo = logo,
        timestamp = os.time()
    })
end

exports("AddTransaction", AddTransaction)

---@param phoneNumber string
---@param page? number
---@param perPage? number
local function GetTransactions(phoneNumber, page, perPage)
    page = math.max(page or 0, 0)
    perPage = math.max(perPage or 5, 1)

    return MySQL.query.await([[
        SELECT amount, company, logo, `timestamp`
        FROM phone_wallet_transactions
        WHERE phone_number = ?

        ORDER BY `timestamp` DESC

        LIMIT ?, ?
    ]], { phoneNumber, (page or 0) * perPage, perPage })
end

BaseCallback("wallet:getBalance", function(source, phoneNumber)
    return GetBalance(source)
end)

-- BuckMe card signature (card-back tap-to-reveal in Wallet-Da9Ipi6P.js):
-- GetCharacterName is framework-provided (qbox/qb/esx/standalone each define
-- their own, see server/custom/frameworks/*), so this works regardless of
-- which framework this server runs.
BaseCallback("wallet:getCardholderName", function(source, phoneNumber)
    local first, last = GetCharacterName(source)

    return (first .. " " .. last):upper()
end)

---Deterministic digit string from a seed -- same seed always produces the
---same digits, so the card number/CVV are stable across relogs instead of
---re-rolling every time the card is opened, without needing a DB column.
---@param seed string
---@param length number
local function DeterministicDigits(seed, length)
    local hash = 5381

    for i = 1, #seed do
        hash = (hash * 33 + string.byte(seed, i)) % 2147483647
    end

    local digits = ""

    for _ = 1, length do
        hash = (hash * 1103515245 + 12345) % 2147483647
        digits = digits .. tostring(hash % 10)
    end

    return digits
end

-- BuckMe card number/CVV (front's masked "•••• •••• •••• XXXX" and the
-- back's CVV, both tap-to-reveal via the same card flip in
-- Wallet-Da9Ipi6P.js): tied to GetIdentifier (the framework's persistent
-- account id -- citizenid for qbox), not the phone number, so it stays the
-- same for this character even if they change phones, and is unique per
-- account rather than per phone.
BaseCallback("wallet:getCardDetails", function(source, phoneNumber)
    local identifier = GetIdentifier(source) or phoneNumber or tostring(source)

    return {
        last4 = DeterministicDigits(identifier .. ":card", 4),
        cvv = DeterministicDigits(identifier .. ":cvv", 3)
    }
end)

---@param page number
---@param recent? true
BaseCallback("wallet:getTransactions", function(source, phoneNumber, page, recent)
    return GetTransactions(phoneNumber, page, recent and 5 or 25)
end)

BaseCallback("wallet:doesNumberExist", function(source, phoneNumber, number)
    local sourceFromNumber = GetSourceFromNumber(number)

    if sourceFromNumber then
        return true
    end

    if Config.TransferOffline then
        return MySQL.scalar.await("SELECT 1 FROM phone_phones WHERE phone_number = ?", { number }) == 1
    end
end, false)

---@param data { amount: number, phoneNumber: string }
BaseCallback("wallet:sendPayment", function(source, phoneNumber, data)
    amount = tonumber(data.amount)

    if not amount or amount <= 0 then
        return { success = false, reason = "INVALID_AMOUNT" }
    end

    if GetBalance(source) < amount then
        return { success = false, reason = "INSUFFICIENT_FUNDS" }
    end

    if type(Config.TransferLimits.Daily) == "number" and Config.TransferLimits.Daily > 0 then
        local spentToday = MySQL.scalar.await("SELECT -SUM(amount) FROM phone_wallet_transactions WHERE phone_number = ? AND amount < 0 AND `timestamp` > DATE_SUB(NOW(), INTERVAL 1 DAY)", { phoneNumber }) or 0

        if spentToday + amount > Config.TransferLimits.Daily then
            return { success = false, reason = "EXCEED_DAILY" }
        end
    elseif Config.TransferLimits?.Daily then
        infoprint("error", "TransferLimits.Daily must be a number and greater than 0, or false.")
    end

    if type(Config.TransferLimits.Weekly) == "number" and Config.TransferLimits.Weekly > 0 then
        local spentWeek = MySQL.scalar.await("SELECT -SUM(amount) FROM phone_wallet_transactions WHERE phone_number = ? AND amount < 0 AND `timestamp` > DATE_SUB(NOW(), INTERVAL 7 DAY)", { phoneNumber }) or 0

        if spentWeek + amount > Config.TransferLimits.Weekly then
            return { success = false, reason = "EXCEED_WEEKLY" }
        end
    elseif Config.TransferLimits?.Weekly then
        infoprint("error", "TransferLimits.Weekly must be a number and greater than 0, or false.")
    end

    local sendToSource = GetSourceFromNumber(data.phoneNumber)
    local added = false

    if sendToSource then
        if sendToSource ~= source then
            added = AddMoney(sendToSource, amount)
        else
            debugprint("Can't send money to yourself (source).", source, sendToSource)
        end
    elseif Config.TransferOffline then
        local identifier = GetIdentifier(source)
        local sendToIdentifier = MySQL.scalar.await("SELECT owner_id FROM phone_phones WHERE phone_number = ?", { data.phoneNumber })

        if sendToIdentifier and sendToIdentifier ~= identifier then
            added = AddMoneyOffline and AddMoneyOffline(sendToIdentifier, amount)
        elseif sendToIdentifier == identifier then
            debugprint("Can't send money to yourself (identifier).", identifier, sendToIdentifier)
        end
    end

    if not added then
        return { success = false, reason = "FAILED_ADD" }
    end

    RemoveMoney(source, amount)
    SendMessage(phoneNumber, data.phoneNumber, "<!SENT-PAYMENT-" .. amount .. "!>")

    GetContact(data.phoneNumber, phoneNumber, function(contact)
        if contact then
            AddTransaction(phoneNumber, -amount, contact.name, contact.avatar)
        else
            AddTransaction(phoneNumber, -amount, data.phoneNumber)
        end
    end)

    GetContact(phoneNumber, data.phoneNumber, function(contact)
        if contact then
            AddTransaction(data.phoneNumber, amount, contact.name, contact.avatar)
        else
            AddTransaction(data.phoneNumber, amount, phoneNumber)
        end
    end)

    return { success = true }
end, nil, {
    defaultReturn = { success = false, reason = "UNKNOWN_ERROR" },
    preventSpam = true,
})
