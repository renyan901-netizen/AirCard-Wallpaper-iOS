<?php
return [
    'admin_user' => 'admin',
    'admin_password' => getenv('LICENSE_ADMIN_PASSWORD') ?: 'CHANGE_ME_NOW',
    'db_path' => __DIR__ . '/data/licenses.sqlite',
];
