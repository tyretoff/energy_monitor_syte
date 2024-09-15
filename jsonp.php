<?php
date_default_timezone_set('UTC');

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

// SQL-запрос к таблице
$query = "SELECT `datetime`, `voltage1`, `voltage2`, `voltage3`, `current1`, `current2`, `current3`, `P` FROM `t_power3`;";
$result = $mysqli->query($query);




while ($record = $result->fetch_row()){
    $all[] =  array(strtotime($record[0]), (float)$record[1], (float)$record[2], (float)$record[3], (float)$record[4], (float)$record[5], (float)$record[6], (float)$record[7]);
}

// Конвертируем данные в JSON формат и выводим их
echo json_encode($all);

// Закрытие соединения с базой данных
$mysqli->close();
?>

