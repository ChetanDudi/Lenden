require('dotenv').config();
const express = require('express');
const app = express();
const mongoose = require('mongoose');
const cors = require('cors');
const cron = require('node-cron');
const { sendReminderEmail } = require('./utils/lendingborrowingotp');
const Transaction = require('./models/transaction');
const User = require('./models/user');
const http = require('http');
const socketio = require('socket.io');
const leoProfanity = require('leo-profanity');

const apiRoutes = require('./routes/api');
const Admin = require('./models/admin');

const PORT = process.env.PORT || 5000;

// CORS Configuration
const allowedOrigins = [
  'https://lenden-backend-kf3c.onrender.com',
  'http://localhost:3000',
  'http://localhost:8080',
  'http://127.0.0.1:3000',
  'http://127.0.0.1:8080',
  'https://lenden-seven.vercel.app',
  'https://lendenbackend.onrender.com'
];

const server = http.createServer(app);
const io = socketio(server, {
  cors: {
    origin: function (origin, callback) {
      if (!origin) return callback(null, true);
      if (allowedOrigins.indexOf(origin) !== -1) return callback(null, true);
      if (/^http:\/\/localhost:\d+$/.test(origin)) return callback(null, true);
      callback(new Error('Not allowed by CORS'));
    },
    methods: ['GET', 'POST'],
    credentials: true,
  },
});

const corsOptions = {
  origin: function (origin, callback) {
    // Allow requests with no origin (like mobile apps or curl requests)
    if (!origin) return callback(null, true);

    // Allow from the list of allowed origins
    if (allowedOrigins.indexOf(origin) !== -1) {
      return callback(null, true);
    }

    // Allow from any localhost port for development
    if (/^http:\/\/localhost:\d+$/.test(origin)) {
      return callback(null, true);
    }

    // Block all other origins
    callback(new Error('Not allowed by CORS'));
  },
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
  allowedHeaders: [
    'Content-Type',
    'Authorization',
    'X-Requested-With',
    'Accept',
    'Origin'
  ],
  credentials: true,
  optionsSuccessStatus: 200 // Some legacy browsers (IE11, various SmartTVs) choke on 204
};

// Middleware
app.use(cors(corsOptions));
app.use(express.json());

// Add preflight handling for complex requests
app.options('*', cors(corsOptions));

// Debug middleware to log all requests
app.use((req, res, next) => {
  console.log(`🌐 ${req.method} ${req.path} - Origin: ${req.headers.origin || 'No origin'} - User-Agent: ${req.headers['user-agent']?.substring(0, 50) || 'No user-agent'}`);
  next();
});

// Routes
app.use('/api', apiRoutes(io));

// Root route handler
app.get('/', (req, res) => {
  res.json({
    message: 'Lenden Backend API is running!',
    version: '1.0.0',
    endpoints: {
      base: '/api',
      documentation: 'API endpoints are available under /api prefix'
    },
    cors: {
      enabled: true,
      origins: corsOptions.origin,
      methods: corsOptions.methods
    }
  });
});

// CORS test endpoint
app.get('/cors-test', (req, res) => {
  res.json({
    message: 'CORS is working!',
    timestamp: new Date().toISOString(),
    headers: req.headers,
    origin: req.headers.origin || 'No origin header'
  });
});

// Catch-all route for undefined paths
app.use('*', (req, res) => {
  res.status(404).json({
    error: 'Route not found',
    message: 'The requested endpoint does not exist',
    availableEndpoints: '/api',
    suggestion: 'Try accessing /api endpoints for available routes'
  });
});

// MongoDB Connection
mongoose.connect(process.env.MONGODB_URI, {
  useNewUrlParser: true,
  useUnifiedTopology: true,
})
.then(async () => {
  console.log('Database Established');
  await Admin.createDefaultAdmin();
  console.log('Default admin ensured');
})
.catch((err) => console.error('Database connection error:', err));

// Initialize reminder scheduler
require('./utils/reminderScheduler');
const {
  initializeMonthlyLeaderboardRewardScheduler,
} = require('./utils/monthlyLeaderboardRewardScheduler');
const { initializeOfferCleanupScheduler } = require('./utils/offerCleanupScheduler');
initializeMonthlyLeaderboardRewardScheduler();
initializeOfferCleanupScheduler();

// Chat and group-chat socket events are handled inside chatController and groupChatController,
// which are wired up through apiRoutes(io) above.

server.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
