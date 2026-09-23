<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') license_json(['ok' => false, 'message' => '仅支持 POST'], 405);
$input = license_request();
$normalizedKey = license_normalize_key((string)($input['license_key'] ?? ''));
$deviceID = license_device((string)($input['device_id'] ?? ''));
if (strlen($normalizedKey) < 12 || strlen($normalizedKey) > 64) license_json(['ok' => false, 'message' => '卡密格式无效'], 400);

$pdo = license_db();
$pdo->beginTransaction();
try {
    $stmt = $pdo->prepare('SELECT * FROM license_keys WHERE key_hash = :key_hash LIMIT 1');
    $stmt->execute(['key_hash' => license_hash($normalizedKey)]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) { $pdo->rollBack(); license_json(['ok' => false, 'message' => '卡密不存在'], 404); }
    if ($row['status'] === 'revoked') { $pdo->rollBack(); license_json(['ok' => false, 'message' => '卡密已被撤销'], 410); }
    if ($row['status'] === 'redeemed' && $row['device_id'] !== $deviceID) {
        $pdo->rollBack();
        license_json(['ok' => false, 'message' => '卡密已绑定其他设备'], 409);
    }
    if ($row['status'] === 'redeemed') {
        $pdo->commit();
        license_json(license_payload($row, '卡密已经兑换过'));
    }

    $now = license_now();
    $expires = $now->modify('+' . ((int)$row['days']) . ' days');
    $update = $pdo->prepare(
        'UPDATE license_keys SET status = "redeemed", device_id = :device_id, ' .
        'redeemed_at = :redeemed_at, expires_at = :expires_at WHERE id = :id'
    );
    $update->execute([
        'device_id' => $deviceID,
        'redeemed_at' => $now->format(DATE_ATOM),
        'expires_at' => $expires->format(DATE_ATOM),
        'id' => $row['id'],
    ]);
    $row['status'] = 'redeemed';
    $row['device_id'] = $deviceID;
    $row['expires_at'] = $expires->format(DATE_ATOM);
    $pdo->commit();
    license_json(license_payload($row, '卡密兑换成功'));
} catch (Throwable $error) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    license_json(['ok' => false, 'message' => '兑换失败，请稍后重试'], 500);
}
