<?php
date_default_timezone_set('UTC');

// Параметры подключения к базе данных
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

// Дополнительный параметр для ограничения количества записей
$limit = isset($_GET['limit']) ? intval($_GET['limit']) : 1000;
$limit = min(5000, max(10, $limit)); // Ограничиваем лимит минимум 10, максимум 5000 записей

// Подготовка SQL запроса с использованием prepared statements
if ($start && $end) {
    // Преобразование Unix timestamp в MySQL datetime формат
    $startDate = date('Y-m-d H:i:s', $start);
    $endDate = date('Y-m-d H:i:s', $end);
    
    $stmt = $mysqli->prepare("SELECT `datetime`, `voltage1`, `voltage2`, `voltage3`, 
                              `current1`, `current2`, `current3`, `P` 
                              FROM `t_power3` 
                              WHERE `datetime` BETWEEN ? AND ? 
                              ORDER BY `datetime` ASC 
                              LIMIT ?");
    
    $stmt->bind_param("ssi", $startDate, $endDate, $limit);
} else {
    // Если диапазон не указан, возвращаем последние записи
    $stmt = $mysqli->prepare("SELECT `datetime`, `voltage1`, `voltage2`, `voltage3`, 
                             `current1`, `current2`, `current3`, `P` 
                             FROM `t_power3` 
                             ORDER BY `datetime` DESC 
                             LIMIT ?");
    
    $stmt->bind_param("i", $limit);
}

$stmt->execute();
$result = $stmt->get_result();

$all = [];
while ($record = $result->fetch_row()) {
    // Преобразуем datetime в Unix timestamp для JavaScript
    $timestamp = strtotime($record[0]);
    $all[] = array(
        $timestamp, 
        (float)$record[1], 
        (float)$record[2], 
        (float)$record[3], 
        (float)$record[4], 
        (float)$record[5], 
        (float)$record[6], 
        (float)$record[7]
    );
}

// Если запрос был без диапазона дат и возвращал данные в обратном порядке,
// нужно их перевернуть для хронологического отображения
if (!$start && !$end && !empty($all)) {
    $all = array_reverse($all);
}

// Устанавливаем заголовок JSON
header('Content-Type: application/json');

// Конвертируем данные в JSON формат и выводим их
echo json_encode($all);

// Закрытие соединения с базой данных
$stmt->close();
$mysqli->close();
?>
