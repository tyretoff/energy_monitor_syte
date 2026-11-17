<?php
date_default_timezone_set('Europe/Moscow');

// Подключение к базе данных (берем общий конфиг из родительской папки)
$configPath = dirname(__DIR__) . '/CFG/config.php';
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

// Проверка ключа доступа
if (!isset($_GET['key']) || $_GET['key'] !== 'bFXcyh') {
    die("Invalid key");
}

// Извлечение параметров из URL
$p1 = isset($_GET['p1']) ? $_GET['p1'] : null;
$p2 = isset($_GET['p2']) ? $_GET['p2'] : null;
$p3 = isset($_GET['p3']) ? $_GET['p3'] : null;
$p4 = isset($_GET['p4']) ? $_GET['p4'] : null;
$p5 = isset($_GET['p5']) ? $_GET['p5'] : null;
$p6 = isset($_GET['p6']) ? $_GET['p6'] : null;
$p7 = isset($_GET['p7']) ? $_GET['p7'] : null;
$p8 = isset($_GET['p8']) ? $_GET['p8'] : null;
$p9 = isset($_GET['p9']) ? $_GET['p9'] : null;
$p10 = isset($_GET['p10']) ? $_GET['p10'] : null;
$p11 = isset($_GET['p11']) ? $_GET['p11'] : null; // energy (A+, кВт*ч)
$p12 = isset($_GET['p12']) ? $_GET['p12'] : null; // energy_t1
$p13 = isset($_GET['p13']) ? $_GET['p13'] : null; // energy_t2
$p14 = isset($_GET['p14']) ? $_GET['p14'] : null; // energy_t3

// Подготовка SQL-запроса для вставки данных в таблицу t_power_sdm
$query = "INSERT INTO t_power_sdm (datetime, voltage1, voltage2, voltage3, current1, current2, current3, P, cos1, cos2, cos3, energy, energy_t1, energy_t2, energy_t3) VALUES (NOW(), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
$stmt = $mysqli->prepare($query);

// Fallback: если структура без колонок energy
if ($stmt === false) {
    $fallbackQuery = "INSERT INTO t_power_sdm (datetime, voltage1, voltage2, voltage3, current1, current2, current3, P, cos1, cos2, cos3) VALUES (NOW(), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
    $stmt = $mysqli->prepare($fallbackQuery);
    if ($stmt === false) {
        die("Prepare failed: " . $mysqli->error);
    }
    $stmt->bind_param("dddddddddd", $p1, $p2, $p3, $p4, $p5, $p6, $p7, $p8, $p9, $p10);
} else {
    $stmt->bind_param("dddddddddddddd", $p1, $p2, $p3, $p4, $p5, $p6, $p7, $p8, $p9, $p10, $p11, $p12, $p13, $p14);
}

// Выполнение запроса
if ($stmt->execute()) {
    echo "Data inserted successfully TIME:" . (time() + 10800);
} else {
    echo "Error inserting data: " . $stmt->error;
}

// Закрытие подготовленного запроса и соединения
$stmt->close();
$mysqli->close();
?>
