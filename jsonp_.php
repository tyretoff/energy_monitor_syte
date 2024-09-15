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

// Получение диапазона дат
$start = isset($_GET['start']) ? $_GET['start'] : null;
$end = isset($_GET['end']) ? $_GET['end'] : null;

if ($start && $end) {
    $startDate = date('Y-m-d H:i:s', strtotime($start));
    $endDate = date('Y-m-d H:i:s', strtotime($end));
    $query = "SELECT `datetime`, `voltage1`, `voltage2`, `voltage3`, `current1`, `current2`, `current3`, `P` FROM `t_power3` WHERE `datetime` BETWEEN '$startDate' AND '$endDate'";
} else {
    $query = "SELECT `datetime`, `voltage1`, `voltage2`, `voltage3`, `current1`, `current2`, `current3`, `P` FROM `t_power3`";
}

$result = $mysqli->query($query);

$all = [];
while ($record = $result->fetch_row()) {
    $all[] = array(strtotime($record[0]), (float)$record[1], (float)$record[2], (float)$record[3], (float)$record[4], (float)$record[5], (float)$record[6], (float)$record[7]);
}

// Конвертируем данные в JSON формат и выводим их
echo json_encode($all);

// Закрытие соединения с базой данных
$mysqli->close();
?>
