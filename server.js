const express = require('express');
const path = require('path');
const { exec } = require('child_process');
const fs = require('fs').promises;
const cookieParser = require('cookie-parser');
const bcrypt = require('bcrypt');
const { createProxyMiddleware } = require('http-proxy-middleware');
require('dotenv').config();

const app = express();
const port = process.env.NODE_PORT || 3000;

// Middleware setup
app.use(cookieParser());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Proxy pro noVNC
app.use('/novnc', express.static('/opt/noVNC', {
    setHeaders: (res) => {
        res.set('Cache-Control', 'no-cache');
    }
}));
app.use(
    '/novnc/websockify',
    createProxyMiddleware({
        target: `http://127.0.0.1:${process.env.WEBSOCKIFY_PORT || '6080'}`,
        ws: true,
        changeOrigin: true,
        logLevel: 'debug',
        onError: (err, req, res) => {
            console.error('Proxy error:', err.message);
            res.status(500).send('Proxy error: ' + err.message);
        }
    })
);

// Authentication middleware
function checkAuth(req, res, next) {
    const session = req.cookies.session;
    const customUsername = process.env.CUSTOM_USERNAME || 'user';
    console.log(`checkAuth: session=${session}, customUsername=${customUsername}, cookies=`, JSON.stringify(req.cookies));
    if (session === 'admin' || session === customUsername) {
        console.log(`checkAuth: Access granted for ${req.path}, session=${session}`);
        return next();
    }
    console.log(`checkAuth: No valid session for ${req.path}, redirecting to /login.html`);
    res.set('Cache-Control', 'no-cache, no-store, must-revalidate');
    res.status(302).redirect('/login.html');
}

// Routes that require authentication
app.get('/', checkAuth, (req, res) => {
    console.log('Serving /index.html');
    res.sendFile(path.join(__dirname, 'public', 'index.html'), {
        headers: { 'Cache-Control': 'no-cache, no-store, must-revalidate' }
    });
});

app.get('/login', (req, res) => {
    const session = req.cookies.session;
    const customUsername = process.env.CUSTOM_USERNAME || 'user';
    console.log(`GET /login: session=${session}, customUsername=${customUsername}`);
    if (session === 'admin' || session === customUsername) {
        console.log(`GET /login: Valid session, returning role=${session}`);
        return res.status(200).json({ role: session });
    }
    console.log(`GET /login: No valid session, returning 401`);
    res.status(401).json({ message: 'Not authenticated' });
});

app.get('/vnc-url', checkAuth, (req, res) => {
    try {
        const host = req.headers['x-forwarded-host'] || req.headers.host || 'localhost';
        const vncUrl = `http://${host}/novnc/vnc.html?autoconnect=true&resize=scale&clipboard=true`;
        console.log(`VNC URL requested: ${vncUrl}`);
        res.json({ vncUrl });
    } catch (err) {
        console.error('Error generating VNC URL:', err.message);
        res.status(500).json({ message: 'Failed to generate VNC URL.', error: err.message });
    }
});

app.post('/toggle-obs', checkAuth, (req, res) => {
    const { action } = req.body;
    console.log(`Toggle OBS: action=${action}`);
    if (action === 'start') {
        const obsCommand = 'export DISPLAY=:99 && obs --startstreaming --disable-studio-mode --verbose 2>&1 | tee -a /home/container/.config/obs-studio/logs/obs.log &';
        exec(obsCommand, (err, stdout, stderr) => {
            if (err) {
                console.error('Error starting OBS:', stderr || err.message);
                return res.status(500).json({ message: 'Failed to start OBS.', error: stderr || err.message });
            }
            console.log('OBS started:', stdout);
            res.json({ message: 'OBS started.' });
        });
    } else if (action === 'stop') {
        exec('pkill -u container obs', (err, stdout, stderr) => {
            if (err && err.code !== 1) {
                console.error('Error stopping OBS:', stderr || err.message);
                return res.status(500).json({ message: 'Failed to stop OBS.', error: stderr || err.message });
            }
            console.log('OBS stopped.');
            res.json({ message: 'OBS stopped.' });
        });
    } else {
        res.status(400).json({ message: 'Invalid action. Use "start" or "stop".' });
    }
});

app.get('/bohemka-bot-config', checkAuth, async (req, res) => {
    try {
        const config = await fs.readFile('/home/container/config.json', 'utf8');
        console.log('Bohemka Bot configuration loaded:', JSON.parse(config).chat?.username);
        res.json({ config });
    } catch (err) {
        console.error('Error reading config.json:', err.message);
        res.status(500).json({ message: 'Failed to load Bohemka Bot configuration.', error: err.message });
    }
});

app.post('/bohemka-bot-config', checkAuth, async (req, res) => {
    const { config } = req.body;
    console.log('Saving Bohemka Bot config');
    if (!config) {
        return res.status(400).json({ message: 'Configuration not provided.' });
    }
    try {
        const newConfig = JSON.parse(config);
        await fs.writeFile('/home/container/config.json', JSON.stringify(newConfig, null, 2), 'utf8');
        console.log('Bohemka Bot configuration saved:', newConfig.chat?.username);
        const restartCommand = `pkill -u container bohemka-bot && /usr/local/bin/bohemka-bot --port 3001 --config /home/container/config.json 2>&1 | tee /home/container/bohemka-bot.log &`;
        exec(restartCommand, (err, stdout, stderr) => {
            if (err) {
                console.error('Error restarting Bohemka Bot:', stderr || err.message);
            } else {
                console.log('Bohemka Bot restarted.');
            }
        });
        res.json({ message: 'Bohemka Bot configuration saved and Bohemka Bot restarted.' });
    } catch (err) {
        console.error('Error saving config.json:', err.message);
        res.status(500).json({ message: 'Failed to save Bohemka Bot configuration.', error: err.message });
    }
});

app.post('/toggle-bohemka-bot', checkAuth, (req, res) => {
    const { action } = req.body;
    console.log(`Toggle Bohemka Bot: action=${action}`);
    const bohemkaBotCommand = `/usr/local/bin/bohemka-bot --port 3001 --config /home/container/config.json 2>&1 | tee /home/container/bohemka-bot.log &`;

    if (action === 'start') {
        exec(bohemkaBotCommand, (err, stdout, stderr) => {
            if (err) {
                console.error('Error starting Bohemka Bot:', stderr || err.message);
                return res.status(500).json({ message: 'Failed to start Bohemka Bot.', error: stderr || err.message });
            }
            console.log('Bohemka Bot started:', stdout);
            res.json({ message: 'Bohemka Bot started.' });
        });
    } else if (action === 'stop') {
        exec('pkill -u container bohemka-bot', (err, stdout, stderr) => {
            if (err && err.code !== 1) {
                console.error('Error stopping Bohemka Bot:', stderr || err.message);
                return res.status(500).json({ message: 'Failed to stop Bohemka Bot.', error: stderr || err.message });
            }
            console.log('Bohemka Bot stopped.');
            res.json({ message: 'Bohemka Bot stopped.' });
        });
    } else if (action === 'restart') {
        const restartCommand = `pkill -u container bohemka-bot && ${bohemkaBotCommand}`;
        exec(restartCommand, (err, stdout, stderr) => {
            if (err) {
                console.error('Error restarting Bohemka Bot:', stderr || err.message);
                return res.status(500).json({ message: 'Failed to restart Bohemka Bot.', error: stderr || err.message });
            }
            console.log('Bohemka Bot restarted:', stdout);
            res.json({ message: 'Bohemka Bot restarted.' });
        });
    } else {
        res.status(400).json({ message: 'Invalid action. Use "start", "stop", or "restart".' });
    }
});

app.post('/change-password', checkAuth, async (req, resqueried) => {
    const session = req.cookies.session;
    const customUsername = process.env.CUSTOM_USERNAME || 'user';
    const { newPassword } = req.body;

    console.log(`Change password attempt: session=${session}`);
    if (session !== customUsername && session !== 'admin') {
        return res.status(403).json({ message: 'You cannot change this password.' });
    }
    if (!newPassword) {
        return res.status(400).json({ message: 'New password is required.' });
    }
    const users = await loadUsers();
    users[session].passwordHash = await bcrypt.hash(newPassword, 10);
    await fs.writeFile('/home/container/data/uzivatele.json', JSON.stringify(users, null, 2));
    console.log(`Password saved for ${session}`);
    res.json({ message: 'Password changed successfully.' });
});

app.post('/reset-user-password', checkAuth, async (req, res) => {
    const session = req.cookies.session;
    const customUsername = process.env.CUSTOM_USERNAME || 'user';
    console.log(`Reset password attempt: session=${session}`);
    if (session !== 'admin') {
        return res.status(403).json({ message: 'Only admin can reset password.' });
    }
    const users = await loadUsers();
    users[customUsername].passwordHash = null;
    await fs.writeFile('/home/container/data/uzivatele.json', JSON.stringify(users, null, 2));
    console.log(`Password reset for ${customUsername}`);
    res.json({ message: `${customUsername}'s password has been reset.` });
});

// Public routes (no auth)
app.get('/login.html', (req, res) => {
    console.log('Serving /login.html');
    res.sendFile(path.join(__dirname, 'public', 'login.html'), {
        headers: { 'Cache-Control': 'no-cache, no-store, must-revalidate' }
    });
});

app.post('/login', async (req, res) => {
    const { username, password } = req.body;
    const customUsername = process.env.CUSTOM_USERNAME || 'user';
    console.log(`Login attempt: username=${username}, customUsername=${customUsername}, body=`, JSON.stringify(req.body));
    try {
        if (!username || !password) {
            console.log('Missing username or password');
            return res.status(400).json({ message: 'Username and password are required.' });
        }
        const users = await loadUsers();

        if (username === 'admin' || username === customUsername) {
            const userData = users[username];
            if (!userData) {
                console.log(`User ${username} not found in users`);
                return res.status(401).json({ message: 'Invalid login credentials.' });
            }
            if (!userData.passwordHash && username === customUsername && password) {
                console.log(`First login for ${username}, setting password`);
                users[username].passwordHash = await bcrypt.hash(password, 10);
                await fs.writeFile('/home/container/data/uzivatele.json', JSON.stringify(users, null, 2));
                res.cookie('session', username, { httpOnly: false, maxAge: 24 * 60 * 60 * 1000, sameSite: 'lax', secure: false });
                console.log(`Cookie set for ${username}`);
                return res.json({ role: username, firstLogin: true });
            } else if (userData.passwordHash && await bcrypt.compare(password, userData.passwordHash)) {
                console.log(`Successful login for ${username}`);
                res.cookie('session', username, { httpOnly: false, maxAge: 24 * 60 * 60 * 1000, sameSite: 'lax', secure: false });
                console.log(`Cookie set for ${username}`);
                return res.json({ role: username });
            } else {
                console.log(`Incorrect password for ${username}`);
                return res.status(401).json({ message: 'Incorrect password.' });
            }
        }
        console.log(`Invalid username: ${username}`);
        res.status(401).json({ message: 'Invalid login credentials.' });
    } catch (err) {
        console.error('Login error:', err.message);
        res.status(500).json({ message: 'Server error during login.', error: err.message });
    }
});

app.post('/logout', (req, res) => {
    console.log('Logging out');
    res.clearCookie('session');
    res.json({ message: 'Logout successful.' });
});

// Static files after specific routes
app.use(express.static(path.join(__dirname, 'public'), {
    setHeaders: (res, path) => {
        res.set('Cache-Control', 'no-cache, no-store, must-revalidate');
    }
}));

// User management
async function loadUsers() {
    const customUsername = process.env.CUSTOM_USERNAME || 'user';
    try {
        const data = await fs.readFile('/home/container/data/uzivatele.json', 'utf8');
        const users = JSON.parse(data);
        if (!users.admin || !users[customUsername]) {
            throw new Error('Users missing in file.');
        }
        console.log(`Users loaded: ${Object.keys(users)}`);
        return users;
    } catch (err) {
        console.error('Failed to load uzivatele.json, creating new:', err.message);
        const defaultUsers = {
            admin: { passwordHash: await bcrypt.hash('Bohemkajede', 10) },
            [customUsername]: { passwordHash: null }
        };
        await fs.writeFile('/home/container/data/uzivatele.json', JSON.stringify(defaultUsers, null, 2));
        console.log(`New uzivatele.json created with admin and ${customUsername}.`);
        return defaultUsers;
    }
}

// Initialize and start server
async function startServer() {
    try {
        await fs.readFile('/home/container/config.json', 'utf8');
        await loadUsers();
        app.listen(port, '0.0.0.0', () => {
            console.log(`Server running on port ${port} and listening on 0.0.0.0`);
        });
    } catch (err) {
        console.error('Failed to initialize server:', err.message);
        process.exit(1);
    }
}

startServer();