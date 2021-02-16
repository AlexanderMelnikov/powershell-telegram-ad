# Пароль разблокированных пользователей AD
$new_password = 'Zx12345'

# Токен и url для запросов к Telegram
$token = "12345"
$url = "https://api.telegram.org/bot$token/"

# Выполняем первый запрос для получения
# последнего сообщения
$result = Invoke-RestMethod -Uri ($url+'getUpdates') -Body @{offset='-1';}
$MessageId = $result.result.message.message_id
$ChatId = $result.result.message.chat.id

# Списпок разрешенных пользователей
$AllowedChatId = @($ChatID)

$users = @()

# Командлет получения сообщений
function Get-TelegramMessage(){
    [CmdletBinding()]

    $result = Invoke-RestMethod -Uri ($url+'getUpdates') -Body @{offset='-1';}
    # Проверяем, что это сообщение новее того
    # что мы получили при запуске скрипта
    # и что пользователь в списке разрешенных
    if (($result.result.message.message_id -gt $MessageId) -and ($result.result.message.chat.id -in $AllowedChatId)){
        return $result.result.message
    }
}

# Получение списка заблокированных пользователей
function Get-LockedUsers(){
    [CmdletBinding()]

    # Массив для наполнения пользователями
    $locked_users = New-Object System.Collections.Generic.List[System.Object]
    $users = Get-ADUser -Filter * -Properties LockedOut | where LockedOut -eq True
    # Если у нас нет заблокированных пользователей
    # функция вернет 0 и остановится
    if ($users.Length -eq 0){
        return 0
    }
    # Добавляем пользователей
    foreach ($user in $users){
        $name = $user.Name
        $sid = $user.SID
        # Пользователь состоит из хэш таблицы
        # с именем и SID. Они добавляются в массив
        $locked_users.Add(@(@{name=$name; SID=$sid}))
    }
    return $locked_users
}

# Командлет для отправки сообщений
function Send-TelegramMessage($Message, $ChatId){
    [CmdletBinding()]

    # Определяем кому отправляем и что
    $form = @{
       chat_id = $ChatId;
       text = $Message;
    }
    $result = Invoke-RestMethod -Uri $($url+'sendMessage') -Body $form
    return $result    
}

# Определяем тип сообщения (какая команда)
function Get-TelegramMessageType($Message){
    # Проверяем что сообщение существует (не пустое)
    if ($Message){
        # Команда должна начинаться на /
        # если это не так - функция остановится
        if ($Message.text[0] -notmatch '/'){
            return $Message.message_id, 0
        }
        # убираем знак / из сообщения
        $text = $Message.text -replace '/',''
        # Если это команда на получение пользователей возвращаем
        # и идентификатор сообщения и его тип
        if ("get_user" -eq $text){
            return $Message.message_id, 1
        }
        # если строка состоит из числа (например /123)
        # возвращаем идентификатор сообщения, тип сообщения и индекс пользователя
        elseif ($text -match "^\d+$"){
            return $Message.message_id, 2, $text
        }
    }
    # если сообщение пустое
    return 0, 0
}

# вечный цикл с таймаутов в 2 секунды
while ($True){
    # Проверяем есть ли новые сообщения
    # Если их нет, то ответ будет пустым
    $response = Get-TelegramMessage
    # Проверяем тип сообщения
    $message_type = Get-TelegramMessageType -Message $response
    # Т.к. мы поличили новое сообщение - мы должны заменить идентификатор
    if ($message_type[0] -ne 0){
        $MessageId = $message_type[0]
    }
    # Проверяем тип сообщения
    if ($message_type[1] -eq 1){
        # Получаем заблокированных пользователей
        $users = Get-LockedUsers
        if ($users -ne 0){
            # Формируем текст для отправки в Telegram
            $full_text = ''
            foreach ($user in $users){
                $name = $user.Name
                $index = $users.indexOf($user)
                $full_text += "Unlock user $name /$index`n"
            }
            Send-TelegramMessage -Message $full_text -ChatId $ChatID
        }
        else {
            Send-TelegramMessage -Message 'Нет заблокированных пользователей' -ChatId $ChatID
        }
    } 
    elseif ($message_type[1] -eq 2){
        # получаем нужного пользователя по индексу
        $user = $users[$message_type[2]]
        # если значение user существует - значит индекс верный
        # если этого индекса нет - какая-то ошибка или нас
        # пытаются обмануть
        if ($user){
            # Разблокируем пользователя
            $SID = $user.SID
            Unlock-AdAccount -Identity $SID
            Set-ADAccountPassword -Identity $SID -Reset -NewPassword (ConvertTo-SecureString -AsPlainText $new_password -Force)
            # отправляем сообщение о разблокировке
            Send-TelegramMessage -Message "Пользователь $($user.Name) разблокирован" -ChatId $ChatID
        }
    }
      
    sleep 2
}