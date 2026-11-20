<?php
date_default_timezone_set('UTC');
ini_set('memory_limit', '128M');

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

// Проверка наличия столбцов энергии
$hasEnergyColumns = false;
$check = $mysqli->query("SHOW COLUMNS FROM `t_power_sdm` LIKE 'energy'");
if ($check && $check->num_rows > 0) {
    $hasEnergyColumns = true;
}

$cols = $hasEnergyColumns
    ? "`datetime`, `voltage1`, `voltage2`, `voltage3`, `current1`, `current2`, `current3`, `P`, `energy`, `energy_t1`, `energy_t2`, `energy_t3`"
    : "`datetime`, `voltage1`, `voltage2`, `voltage3`, `current1`, `current2`, `current3`, `P`";

function formatRecord($record, $hasEnergy) {
    $row = array(
        strtotime($record[0]),
        (float)$record[1],
        (float)$record[2],
        (float)$record[3],
        (float)$record[4],
        (float)$record[5],
        (float)$record[6],
        (float)$record[7]
    );
    if ($hasEnergy) {
        $row[] = ($record[8] !== null) ? (float)$record[8] : null;
        $row[] = ($record[9] !== null) ? (float)$record[9] : null;
        $row[] = ($record[10] !== null) ? (float)$record[10] : null;
        $row[] = ($record[11] !== null) ? (float)$record[11] : null;
    }
    return $row;
}

// Получение диапазона дат из параметров запроса
$start = isset($_GET['start']) ? intval($_GET['start']) : null;
$end = isset($_GET['end']) ? intval($_GET['end']) : null;
$range = isset($_GET['range']) ? $_GET['range'] : null;

if ($range === 'all') {
    $stmt = $mysqli->prepare("SELECT $cols FROM `t_power_sdm` ORDER BY `datetime` ASC");
} elseif ($start && $end) {
    $startDate = date('Y-m-d H:i:s', $start);
    $endDate = date('Y-m-d H:i:s', $end);
    $stmt = $mysqli->prepare("SELECT $cols FROM `t_power_sdm` WHERE `datetime` BETWEEN ? AND ? ORDER BY `datetime` ASC");
    $stmt->bind_param("ss", $startDate, $endDate);
} else {
    $startDate = date('Y-m-d H:i:s', strtotime('-1 day'));
    $stmt = $mysqli->prepare("SELECT $cols FROM `t_power_sdm` WHERE `datetime` >= ? ORDER BY `datetime` ASC");
    $stmt->bind_param("s", $startDate);
}

$stmt->execute();
$result = $stmt->get_result();

// Если данных нет за сутки, загружаем последние доступные данные
if ($result->num_rows === 0 && !$start && !$end && $range !== 'all') {
    $stmt->close();
    $stmt = $mysqli->prepare("SELECT $cols FROM `t_power_sdm` ORDER BY `datetime` DESC LIMIT 10000");
    $stmt->execute();
    $result = $stmt->get_result();
    
    $tempData = [];
    while ($record = $result->fetch_row()) {
        $tempData[] = $record;
    }
    $tempData = array_reverse($tempData);
    
    $all = [];
    foreach ($tempData as $record) {
        $all[] = formatRecord($record, $hasEnergyColumns);
    }
    
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
    $all[] = formatRecord($record, $hasEnergyColumns);
}

echo json_encode($all);

$mysqli->close();
?>
