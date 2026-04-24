const express = require('express');
const { body, validationResult } = require('express-validator');
const {
  CognitoIdentityProviderClient,
  InitiateAuthCommand,
  SignUpCommand,
  ConfirmSignUpCommand,
  ForgotPasswordCommand,
  ConfirmForgotPasswordCommand,
  GlobalSignOutCommand,
  ResendConfirmationCodeCommand,
} = require('@aws-sdk/client-cognito-identity-provider');
const { logger } = require('../middleware/logger');

const router = express.Router();

const cognito = new CognitoIdentityProviderClient({ region: process.env.AWS_REGION });
const CLIENT_ID = process.env.COGNITO_CLIENT_ID;

function validate(req, res, next) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
  next();
}

// POST /api/v1/auth/signup
router.post('/signup',
  body('email').isEmail().normalizeEmail(),
  body('password').isLength({ min: 8 }).matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])/),
  body('name').trim().notEmpty().isLength({ max: 100 }),
  validate,
  async (req, res, next) => {
    try {
      const { email, password, name } = req.body;
      await cognito.send(new SignUpCommand({
        ClientId: CLIENT_ID,
        Username: email,
        Password: password,
        UserAttributes: [
          { Name: 'email', Value: email },
          { Name: 'name', Value: name },
        ],
      }));
      res.status(201).json({ message: 'Account created. Check your email to verify.' });
    } catch (err) {
      if (err.name === 'UsernameExistsException') {
        return res.status(409).json({ error: 'Email already registered' });
      }
      next(err);
    }
  }
);

// POST /api/v1/auth/confirm
router.post('/confirm',
  body('email').isEmail().normalizeEmail(),
  body('code').trim().notEmpty().isLength({ min: 6, max: 6 }),
  validate,
  async (req, res, next) => {
    try {
      await cognito.send(new ConfirmSignUpCommand({
        ClientId: CLIENT_ID,
        Username: req.body.email,
        ConfirmationCode: req.body.code,
      }));
      res.json({ message: 'Email verified. You can now sign in.' });
    } catch (err) {
      if (err.name === 'CodeMismatchException') return res.status(400).json({ error: 'Invalid confirmation code' });
      next(err);
    }
  }
);

// POST /api/v1/auth/signin
router.post('/signin',
  body('email').isEmail().normalizeEmail(),
  body('password').notEmpty(),
  validate,
  async (req, res, next) => {
    try {
      const result = await cognito.send(new InitiateAuthCommand({
        AuthFlow: 'USER_PASSWORD_AUTH',
        ClientId: CLIENT_ID,
        AuthParameters: {
          USERNAME: req.body.email,
          PASSWORD: req.body.password,
        },
      }));
      const auth = result.AuthenticationResult;
      res.json({
        accessToken: auth.AccessToken,
        idToken: auth.IdToken,
        refreshToken: auth.RefreshToken,
        expiresIn: auth.ExpiresIn,
      });
    } catch (err) {
      if (err.name === 'NotAuthorizedException' || err.name === 'UserNotFoundException') {
        return res.status(401).json({ error: 'Invalid credentials' });
      }
      if (err.name === 'UserNotConfirmedException') {
        return res.status(403).json({ error: 'Email not verified' });
      }
      next(err);
    }
  }
);

// POST /api/v1/auth/refresh
router.post('/refresh',
  body('refreshToken').notEmpty(),
  validate,
  async (req, res, next) => {
    try {
      const result = await cognito.send(new InitiateAuthCommand({
        AuthFlow: 'REFRESH_TOKEN_AUTH',
        ClientId: CLIENT_ID,
        AuthParameters: { REFRESH_TOKEN: req.body.refreshToken },
      }));
      const auth = result.AuthenticationResult;
      res.json({ accessToken: auth.AccessToken, idToken: auth.IdToken, expiresIn: auth.ExpiresIn });
    } catch (err) {
      if (err.name === 'NotAuthorizedException') return res.status(401).json({ error: 'Invalid refresh token' });
      next(err);
    }
  }
);

// POST /api/v1/auth/forgot-password
router.post('/forgot-password',
  body('email').isEmail().normalizeEmail(),
  validate,
  async (req, res, next) => {
    try {
      await cognito.send(new ForgotPasswordCommand({ ClientId: CLIENT_ID, Username: req.body.email }));
      res.json({ message: 'Password reset code sent to your email' });
    } catch {
      // Always return success to avoid user enumeration
      res.json({ message: 'Password reset code sent to your email' });
    }
  }
);

// POST /api/v1/auth/reset-password
router.post('/reset-password',
  body('email').isEmail().normalizeEmail(),
  body('code').trim().notEmpty(),
  body('newPassword').isLength({ min: 8 }).matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])/),
  validate,
  async (req, res, next) => {
    try {
      await cognito.send(new ConfirmForgotPasswordCommand({
        ClientId: CLIENT_ID,
        Username: req.body.email,
        ConfirmationCode: req.body.code,
        Password: req.body.newPassword,
      }));
      res.json({ message: 'Password reset successfully' });
    } catch (err) {
      if (err.name === 'CodeMismatchException') return res.status(400).json({ error: 'Invalid code' });
      if (err.name === 'ExpiredCodeException') return res.status(400).json({ error: 'Code expired' });
      next(err);
    }
  }
);

// POST /api/v1/auth/signout
router.post('/signout',
  body('accessToken').notEmpty(),
  validate,
  async (req, res, next) => {
    try {
      await cognito.send(new GlobalSignOutCommand({ AccessToken: req.body.accessToken }));
      res.json({ message: 'Signed out successfully' });
    } catch (err) {
      next(err);
    }
  }
);

module.exports = router;
