<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

$host = '127.0.0.1';
$db   = 'entertok';
$user = 'root';
$pass = ''; // XAMPP default: empty password
$charset = 'utf8mb4';

$dsn = "mysql:host=$host;dbname=$db;charset=$charset";
$options = [
    PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    PDO::ATTR_EMULATE_PREPARES   => false,
];

try {
    $pdo = new PDO($dsn, $user, $pass, $options);
} catch (\PDOException $e) {
    echo json_encode(['error' => 'Database connection failed: ' . $e->getMessage()]);
    exit;
}

$method = $_SERVER['REQUEST_METHOD'];
$uri = $_SERVER['REQUEST_URI'];
$path = parse_url($uri, PHP_URL_PATH);
$path = str_replace('/api/v1/', '', $path);

// Get feed posts
if ($method === 'GET' && ($path === 'posts/feed' || $path === 'posts')) {
    $stmt = $pdo->query("
        SELECT p.id, p.content, p.media_url, p.thumbnail, p.media_type, p.like_count, p.comment_count, p.share_count, p.location, p.created_at,
               u.id as user_id, u.username, u.full_name, u.profile_image
        FROM posts p
        LEFT JOIN users u ON p.user_id = u.id
        ORDER BY p.created_at DESC
        LIMIT 20
    ");
    $posts = $stmt->fetchAll();
    
    // Nest user info in user object
    foreach ($posts as &$post) {
        $post['is_liked'] = false;
        $post['user'] = [
            'id' => $post['user_id'] ?? 0,
            'username' => $post['username'] ?? '',
            'full_name' => $post['full_name'] ?? '',
            'profile_image' => $post['profile_image'] ?? '',
            'is_following' => false
        ];
        unset($post['user_id'], $post['username'], $post['full_name'], $post['profile_image']);
    }
    
    echo json_encode(['posts' => $posts]);
    exit;
}

// Get single post
if ($method === 'GET' && preg_match('/posts\/(\d+)/', $path, $matches)) {
    $postId = $matches[1];
    $stmt = $pdo->prepare("
        SELECT p.*, u.id as user_id, u.username, u.full_name, u.profile_image
        FROM posts p
        LEFT JOIN users u ON p.user_id = u.id
        WHERE p.id = ?
    ");
    $stmt->execute([$postId]);
    $post = $stmt->fetch();
    
    if ($post) {
        echo json_encode($post);
    } else {
        echo json_encode(['error' => 'Post not found']);
    }
    exit;
}

// Auth - get current user
if ($method === 'GET' && $path === 'auth/me') {
    // For demo, return first user
    $stmt = $pdo->query("SELECT * FROM users LIMIT 1");
    $user = $stmt->fetch();
    if ($user) {
        echo json_encode($user);
    } else {
        echo json_encode(['error' => 'No user found']);
    }
    exit;
}

// Default response
echo json_encode(['message' => 'EnterTok API', 'status' => 'running']);
