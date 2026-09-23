<?php
declare(strict_types=1);

function license_config(): array {
    static $config;
    if ($config !== null) return $config;
    $defaults = require __DIR__ . '/config.example.php';
    $custom = is_file(__DIR__ . '/config.php') ? require __DIR__ . '/config.php' : [];
    $config = array_merge($defaults, is_array($custom) ? $custom : []);
    return $config;
}

function license_json(array $payload, int $status = 200): void {
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function license_request(): array {
    $raw = file_get_contents('php://input') ?: '';
    $data = json_decode($raw, true);
    return is_array($data) ? $data : $_POST;
}

function license_db(): PDO {
    static $pdo;
    if ($pdo instanceof PDO) return $pdo;
    $config = license_config();
    $dir = dirname($config['db_path']);
    if (!is_dir($dir)) mkdir($dir, 0750, true);
    $pdo = new PDO('sqlite:' . $config['db_path']);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->exec('CREATE TABLE IF NOT EXISTS license_keys (' .
        'id INTEGER PRIMARY KEY AUTOINCREMENT,' .
        'key_hash TEXT NOT NULL UNIQUE,' .
        'key_hint TEXT NOT NULL,' .
        'days INTEGER NOT NULL,' .
        'status TEXT NOT NULL DEFAULT "unused",' .
        'device_id TEXT,' .
        'redeemed_at TEXT,' .
        'expires_at TEXT,' .
        'created_at TEXT NOT NULL,' .
        'note TEXT)');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_license_device ON license_keys(device_id)');
    return $pdo;
}

function license_normalize_key(string $value): string {
    return strtoupper(preg_replace('/[^A-Z0-9]/i', '', trim($value)) ?? '');
}

function license_hash(string $normalizedKey): string {
    return hash('sha256', $normalizedKey);
}

function license_device(string $value): string {
    $value = strtolower(trim($value));
    if (!preg_match('/^[a-f0-9]{32}$/', $value)) {
        license_json(['ok' => false, 'message' => '设备标识格式无效'], 400);
    }
    return $value;
}

function license_now(): DateTimeImmutable {
    return new DateTimeImmutable('now', new DateTimeZone('UTC'));
}

function license_date(?string $value): ?DateTimeImmutable {
    return $value ? new DateTimeImmutable($value, new DateTimeZone('UTC')) : null;
}

function license_payload(?array $row, string $message = ''): array {
    $expires = license_date($row['expires_at'] ?? null);
    $remaining = $expires ? max(0, $expires->getTimestamp() - license_now()->getTimestamp()) : 0;
    $active = $row !== null && ($row['status'] ?? '') === 'redeemed' && $remaining > 0;
    return [
        'ok' => true,
        'active' => $active,
        'expires_at' => $expires?->format(DATE_ATOM),
        'remaining_seconds' => $remaining,
        'message' => $message,
    ];
}

function license_for_device(string $deviceID): ?array {
    $stmt = license_db()->prepare(
        'SELECT * FROM license_keys WHERE device_id = :device_id AND status = "redeemed" ' .
        'AND expires_at IS NOT NULL ORDER BY expires_at DESC LIMIT 1'
    );
    $stmt->execute(['device_id' => $deviceID]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    return $row ?: null;
}

function license_require_admin(): void {
    $config = license_config();
    $validUser = hash_equals((string)$config['admin_user'], $_SERVER['PHP_AUTH_USER'] ?? '');
    $validPassword = hash_equals((string)$config['admin_password'], $_SERVER['PHP_AUTH_PW'] ?? '');
    if (!$validUser || !$validPassword) {
        header('WWW-Authenticate: Basic realm="AirCard License Admin"');
        http_response_code(401);
        echo 'Authentication required';
        exit;
    }
}

function license_html(string $value): string {
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function license_generate_key(): string {
    $hex = strtoupper(bin2hex(random_bytes(8)));
    return 'AC-' . implode('-', str_split($hex, 4));
}
