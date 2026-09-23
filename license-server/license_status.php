<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') license_json(['ok' => false, 'message' => '仅支持 POST'], 405);
$input = license_request();
$deviceID = license_device((string)($input['device_id'] ?? ''));
$row = license_for_device($deviceID);
license_json(license_payload($row, $row ? '授权状态已更新' : '当前设备没有有效卡密'));
