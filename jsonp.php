<?php
date_default_timezone_set('UTC');
ini_set('memory_limit', '512M');

// Параметры подключения к базе данных
//$servername = "localhost";
//$username = "s******_power";
//$password = "MP*********d4";
//$dbname = "s*****_power";

// Подключение к базе данных
$configPath = __DIR__ . '/CFG/config.php';
if (!file_exists($configPath)) {
    die("Configuration file not found");
}

$config = require($configPath);

if (!$config || !isset($config['servername'], $config['username'], $config['password'], $config['dbname'])) {
    die("Invalid configuration file");
}

$mysqli = new mysqli($config['servername'], $config['username'], $config['password'], $config['dbname']);

// Проверка подключения
if ($mysqli->connect_error) {
    die("Connection failed: " . $mysqli->connect_error);
}


// Получение диапазона дат из параметров запроса
$start = isset($_GET['start']) ? intval($_GET['start']) : null;
$end = isset($_GET['end']) ? intval($_GET['end']) : null;

$range = isset($_GET['range']) ? $_GET['range'] : null;

if ($range === 'all') {
    // Загружаем все данные
    $stmt = $mysqli->prepare("SELECT `datetime`, `voltage1`, `voltage2`, `voltage3`, `current1`, `current2`, `current3`, `P` FROM `t_power3` ORDER BY `datetime` ASC");
} elseif ($start && $end) {
    // Преобразование Unix timestamp в MySQL datetime формат
    $startDate = date('Y-m-d H:i:s', $start);
    $endDate = date('Y-m-d H:i:s', $end);
    $stmt = $mysqli->prepare("SELECT `datetime`, `voltage1`, `voltage2`, `voltage3`, `current1`, `current2`, `current3`, `P` FROM `t_power3` WHERE `datetime` BETWEEN ? AND ? ORDER BY `datetime` ASC");
    $stmt->bind_param("ss", $startDate, $endDate);
} else {
    // По умолчанию - пытаемся загрузить данные за последние сутки
    $startDate = date('Y-m-d H:i:s', strtotime('-1 day'));
    $stmt = $mysqli->prepare("SELECT `datetime`, `voltage1`, `voltage2`, `voltage3`, `current1`, `current2`, `current3`, `P` FROM `t_power3` WHERE `datetime` >= ? ORDER BY `datetime` ASC");
    $stmt->bind_param("s", $startDate);
}

$stmt->execute();
$result = $stmt->get_result();

// Если данных нет и это запрос по умолчанию (без параметров), загружаем последние доступные данные
if ($result->num_rows === 0 && !$start && !$end && $range !== 'all') {
    $stmt->close();
    // Загружаем последние 10000 записей (или все, если их меньше)
    $stmt = $mysqli->prepare("SELECT `datetime`, `voltage1`, `voltage2`, `voltage3`, `current1`, `current2`, `current3`, `P` FROM `t_power3` ORDER BY `datetime` DESC LIMIT 10000");
    $stmt->execute();
    $result = $stmt->get_result();
    
    // Переворачиваем результат для правильного порядка (от старых к новым)
    $tempData = [];
    while ($record = $result->fetch_row()) {
        $tempData[] = $record;
    }
    $tempData = array_reverse($tempData);
    
    // Формируем результат
    $all = [];
    foreach ($tempData as $record) {
        $all[] = array(strtotime($record[0]), (float)$record[1], (float)$record[2], (float)$record[3], (float)$record[4], (float)$record[5], (float)$record[6], (float)$record[7]);
    }
    
    // Добавляем метаданные о том, что это последние доступные данные
    $response = [
        'data' => $all,
        'fallback' => true,
        'message' => 'Загружены последние доступные данные'
    ];
    
    echo json_encode($response);
    $stmt->close();
    $mysqli->close();
    exit;
}



$all = [];
while ($record = $result->fetch_row()){
    $all[] =  array(strtotime($record[0]), (float)$record[1], (float)$record[2], (float)$record[3], (float)$record[4], (float)$record[5], (float)$record[6], (float)$record[7]);
}

// Конвертируем данные в JSON формат и выводим их
echo json_encode($all);

// Закрытие соединения с базой данных
$mysqli->close();
?>

