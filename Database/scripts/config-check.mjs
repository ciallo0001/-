import {readConfig,validateConfig} from './config.mjs';
try { validateConfig(readConfig()); console.log('Database configuration valid. Secrets hidden.'); }
catch(error) {console.error(error.message);process.exitCode=1;}
