<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';
license_require_admin();

$pdo = license_db();
$generated = [];
$message = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';
    if ($action === 'generate') {
        $days = max(1, min(3650, (int)($_POST['days'] ?? 30)));
        $quantity = max(1, min(500, (int)($_POST['quantity'] ?? 1)));
        $note = trim((string)($_POST['note'] ?? ''));
        $insert = $pdo->prepare(
            'INSERT INTO license_keys (key_hash, key_hint, days, created_at, note) ' .
            'VALUES (:key_hash, :key_hint, :days, :created_at, :note)'
        );
        for ($i = 0; $i < $quantity; $i++) {
            do {
                $key = license_generate_key();
                $hash = license_hash(license_normalize_key($key));
                $check = $pdo->prepare('SELECT 1 FROM license_keys WHERE key_hash = :key_hash');
                $check->execute(['key_hash' => $hash]);
            } while ($check->fetchColumn());
            $insert->execute([
                'key_hash' => $hash,
                'key_hint' => substr($key, -4),
                'days' => $days,
                'created_at' => license_now()->format(DATE_ATOM),
                'note' => $note,
            ]);
            $generated[] = $key;
        }
        $message = '已生成 ' . count($generated) . ' 张卡密；明文只在本页显示，请立即保存。';
    } elseif ($action === 'revoke') {
        $stmt = $pdo->prepare('UPDATE license_keys SET status = "revoked" WHERE id = :id');
        $stmt->execute(['id' => (int)($_POST['id'] ?? 0)]);
        $message = '卡密已撤销。';
    }
}

$rows = $pdo->query('SELECT * FROM license_keys ORDER BY id DESC LIMIT 100')->fetchAll(PDO::FETCH_ASSOC);
?><!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>AirCard 卡密后台</title>
<style>body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;max-width:1000px;margin:32px auto;padding:0 16px;color:#202124;background:#f6f7f9}main{background:#fff;padding:24px;border-radius:12px;box-shadow:0 2px 14px #0001}h1{margin-top:0}label{display:block;margin:12px 0 4px;font-weight:600}input,textarea,button{font:inherit;padding:9px;border:1px solid #ccd1d8;border-radius:7px}input{width:180px}textarea{width:100%;box-sizing:border-box}button{cursor:pointer;background:#1677ff;color:#fff;border:0}.danger{background:#d93025}.notice{padding:10px;background:#e7f3ff;border-radius:7px;margin:12px 0}table{border-collapse:collapse;width:100%;margin-top:24px;font-size:14px}th,td{text-align:left;padding:9px;border-bottom:1px solid #e5e7eb}code{font-size:12px}</style>
</head>
<body><main>
<h1>AirCard 卡密后台</h1>
<?php if ($message): ?><div class="notice"><?= license_html($message) ?></div><?php endif; ?>
<form method="post">
<input type="hidden" name="action" value="generate">
<label>使用天数</label><input type="number" name="days" value="30" min="1" max="3650">
<label>生成数量</label><input type="number" name="quantity" value="1" min="1" max="500">
<label>备注</label><input type="text" name="note" placeholder="例如：测试用户">
<p><button type="submit">生成卡密</button></p>
</form>
<?php if ($generated): ?><h2>新卡密</h2><textarea rows="<?= count($generated) + 1 ?>" readonly><?= license_html(implode("\n", $generated)) ?></textarea><?php endif; ?>
<h2>最近卡密</h2>
<table><thead><tr><th>ID</th><th>后四位</th><th>天数</th><th>状态</th><th>设备</th><th>到期</th><th>操作</th></tr></thead><tbody>
<?php foreach ($rows as $row): ?><tr>
<td><?= (int)$row['id'] ?></td><td><code><?= license_html($row['key_hint']) ?></code></td><td><?= (int)$row['days'] ?></td><td><?= license_html($row['status']) ?></td>
<td><code><?= license_html($row['device_id'] ? substr($row['device_id'], 0, 8) . '...' : '-') ?></code></td><td><?= license_html($row['expires_at'] ?: '-') ?></td>
<td><?php if ($row['status'] !== 'revoked'): ?><form method="post"><input type="hidden" name="action" value="revoke"><input type="hidden" name="id" value="<?= (int)$row['id'] ?>"><button class="danger" type="submit">撤销</button></form><?php endif; ?></td>
</tr><?php endforeach; ?>
</tbody></table>
</main></body></html>
