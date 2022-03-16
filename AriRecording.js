'use strict';

// https://wiki.asterisk.org/wiki/display/AST/ARI+and+Bridges%3A+Basic+Mixing+Bridges
//      source: bridge-dial.js
// Nodejs ari
//      https://github.com/asterisk/node-ari-client
// ARI object structure
//      https://wiki.asterisk.org/wiki/display/AST/Asterisk+18+REST+Data+Models

const mARI = require('ari-client');
const mUtil = require('util');
const mFs = require('fs');
const mPath = require('path');
//remove const mSTT = require('@google-cloud/speech');
const ami = require('./ami');

const AppName = "AriRecording";
const AstSpoolDir = '/var/spool/asterisk/recording';
const RecordingAudioExt = 'wav';
const RecordingSTTExt = 'txt';
const MaxRecordingSilence = 1; // seconds. 0 is no limitation
const MaxRecordingTime = 0; // seconds. 0 is no limitation
const STTFlag = 'flag';
const STTText = 'text';
const STTFuncs = 'funcs';

const AppType = {
    // 1-1 call
    Dial: "ARI-Dial",
    Dialed: "Internal-Dialed",

    Conference: "ARI-Conference",
}

const CallType = {
	Caller: "caller",
	Callee: "callee",
}

/*
    {AppType}
        {caller_callee channel name} // Recording directory path
            {STT flag}              // Flag for indicate start STT
            {STT Text}              // Path to output text file
            {STT functions queue}   // Function array for STT
        {conference room}           // For Conference ??? (Duplicate)
            {user extension 1}
            {user extension 2}
            {user extension n}
*/
var RecordingInfos = {};

// Connect to ari of asterisk (ari.conf)
mARI.connect('http://localhost:8088', 'ntdon', 'ntdon', clientLoaded);

// export GOOGLE_APPLICATION_CREDENTIALS=./GG-STT-Certificate.json
process.env.GOOGLE_APPLICATION_CREDENTIALS = __dirname + '/GG-STT-Certificate.json'
//mUtil.log(process.env);

// handler for client being loaded
function clientLoaded (err, client) {
    if (err) {
        throw err;
    }

    // handler for StasisStart event
    function stasisStart(event, channel) {
        // handle for each type of argument
        switch (event.args[0])
        {
            // Dial to PJSIP/6001 (event.args[1])
            // Dialplan: same = n,Stasis(TestARI,ari-Dial,PJSIP/6001)
            // After callee hangup or reject, it will continue next dialplan: channel.continueInDialplan
            case AppType.Dial:
                CreateRecordingInfo('', '');
                channel.answer(function(err) {
                    if (err) {
                        throw err;
                    }

                    originate(event, channel);
                });
                break;
            
            // Invoke by dialed.originate
            case AppType.Dialed:
                break;
            default:
                
                break;
        }
    }

    function originate(event, channel) {
        var dialed = client.Channel();

        channel.on('StasisEnd', function(event, channel) {
            hangupDialed(channel, dialed);
        });

        dialed.on('ChannelDestroyed', function(event, dialed) {
            hangupOriginal(channel, dialed);
        });

        dialed.on('StasisStart', function(event, dialed) {
            joinMixingBridge(channel, dialed);
        });

        mUtil.log("originate dialed.name:%s dialed.id:%s", dialed.name, dialed.id);
        dialed.originate(
            //{endpoint: process.argv[2], app: AppName, appArgs: 'dialed'},
            {callerId: mUtil.format('%s <%s>', channel.caller.name, channel.caller.number),
                endpoint: event.args[1], app: AppName, appArgs: AppType.Dialed},
            function(err, dialed) {
                if (err) {
                    throw err;
                }
        });
    }

    // handler for original channel hanging up so we can gracefully hangup the
    // other end
    function hangupDialed(channel, dialed) {

        // hangup the other end
        dialed.hangup(function(err) {
            // ignore error since dialed channel could have hung up, causing the
            // original channel to exit Stasis
        });
    }

    // handler for the dialed channel hanging up so we can gracefully hangup the
    // other end
    function hangupOriginal(channel, dialed) {

        // hangup the other end
        channel.hangup(function(err) {
            // ignore error since original channel could have hung up, causing the
            // dialed channel to exit Stasis
        });

        // continue dialplan when callee reject or hangup
        //channel.continueInDialplan(function(err) {
        //});
    }

    // handler for dialed channel entering Stasis
    function joinMixingBridge(channel, dialed) {
        var bridge = client.Bridge();

        dialed.on('StasisEnd', function(event, dialed) {
            dialedExit(dialed, bridge);
        });

        dialed.answer(function(err) {
            if (err) {
                throw err;
            }
        });

        bridge.create({type: 'mixing'}, function(err, bridge) {
            if (err) {
                throw err;
            }

            addChannelsToBridge(channel, dialed, bridge);
        });
    }

    // handler for the dialed channel leaving Stasis
    function dialedExit(dialed, bridge) {

        bridge.destroy(function(err) {
            if (err) {
                throw err;
            }
        });
    }

    // handler for new mixing bridge ready for channels to be added to it
    function addChannelsToBridge(channel, dialed, bridge) {

        bridge.addChannel({channel: [channel.id, dialed.id]}, function(err) {
            if (err) {
                throw err;
            }
        });

        // https://github.com/asterisk/node-ari-client/issues/108
        // snoopChannel for recording audio to wav file on caller input audio
        client.channels.snoopChannel(
            //{app: AppName, channelId: channel.id, snoopId: channel.id + '_snoop', spy: 'both', whisper: 'out'},
            {app: AppName, channelId: channel.id, spy: 'in'},
            function (err, channelIn) {
                // Create recording info object
                CreateRecordingInfo(channel.name, dialed.name);
                
                // Recording directly
                var channelRecordPath = AriDialRecordingName(channel.name, dialed.name, CallType.Caller);
                StartRecording(client, channelIn.id, channelRecordPath, 1);
            });

        // snoopChannel for recording audio to wav file on callee input audio
        client.channels.snoopChannel(
            //{app: AppName, channelId: dialed.id, snoopId: dialed.id + '_snoop', spy: 'both', whisper: 'out'},
            {app: AppName, channelId: dialed.id, spy: 'in'},
            function (err, dialedIn) {
                // Create recording info object
                CreateRecordingInfo(channel.name, dialed.name);

                // Recording directly
                var dialedRecordPath = AriDialRecordingName(channel.name, dialed.name, CallType.Callee);
                StartRecording(client, dialedIn.id, dialedRecordPath, 1);
            });
    }

    client.on('StasisStart', stasisStart);

    client.on('RecordingStarted', function(event, recording) {
        mUtil.log("RecordingStarted time:%s", (new Date()).toISOString());
    });

    client.on('RecordingFailed', function(event, recording) {
        mUtil.log("RecordingFailed name:%s cause:%s", recording.name, recording.cause);
    });

    client.on('RecordingFinished', function(event, recording) {
        mUtil.log("RecordingFinished time:%s", (new Date()).toISOString());

        // target_uri: 'channel:1625737796.1417',
        var channelId = recording.target_uri.replace('channel:', '');
        // name: 'ARI-Dial/7001-00000196_7002-00000197/caller.004',
        var recordingNames = recording.name.split('.');
        var recordPath = recordingNames[0];
        var index = parseInt(recordingNames[1]) + 1;
        
        // Continue recording after stop
        StartRecording(client, channelId, recordPath, index);
        
        // Add recording info and STT
        var recordingDirObj = AddRecordingInfo(recording.name, recording.format, recording.duration);
        if (recordingDirObj && !recordingDirObj[STTFlag])
        {
            StartSendSTT(recording.name, recordingDirObj);
        }
    });

    client.start(AppName);
}

// @@@@@@@@@@@@@@@@@@ Recording Handle @@@@@@@@@@@@@@@@@@

function StartRecording(client, channelId, file, index)
{
    mUtil.log("StartRecording time:%s", (new Date()).toISOString());
    
    // Recording name - absolute path to recording file without extension
    var channelRecordName = AriDialRecordingNameWithIndex(file, index);

    // Start recording
    //var channelRecording = client.LiveRecording(client, {name: channelRecordName});
    client.channels.record(
        {channelId: channelId,
        //name: channelRecording.name,
        name: channelRecordName,
        format: RecordingAudioExt,
        //beep: true,
        ifExists: 'overwrite',
        maxDurationSeconds: MaxRecordingTime,
        maxSilenceSeconds: MaxRecordingSilence},
        function (err, liverecording) {
            if (err) {
                mUtil.log("StartRecording %s is started recording %s", channelRecordName, err.message);
            }
            else {
                mUtil.log("StartRecording time:%s", (new Date()).toISOString());
                mUtil.log("StartRecording new file:%s", channelRecordName);
            }
        }
    );
}

// @@@@@@@@@@@@@@@@@@ Recording Handle @@@@@@@@@@@@@@@@@@

// @@@@@@@@@@@@@@@@@@ STT Handle @@@@@@@@@@@@@@@@@@

async function StartSendSTT(recordingName, recordingDirObj)
{
    // Start send STT
    recordingDirObj[STTFlag] = true;
    
    // Get/Remove first STT func from array
    var func = recordingDirObj[STTFuncs].shift();
    
    // Have STT func
    while (func)
    {
        // Send STT
        await func();
        //func();
    
        // Get new STT func for continue STT
        func = recordingDirObj[STTFuncs].shift();
    }

    // Stop send STT
    recordingDirObj[STTFlag] = false;
    
    // Remove recordingDirObj if have not any data
    DeleteRecordingInfo(recordingName);
}

/*
// Send content(string base64) to Google Speech To Text (GG STT)
async function sendSTT_old(wavFile, txtFile, duration) {
    mUtil.log("GG STT start");
    if (!mFs.existsSync(wavFile)) {
        mUtil.log("%s does not exist", wavFile);
        return;
    }

    // Creates a client
    const client = new mSTT.SpeechClient();

    // Init configuration for content argument
    //const encoding = 'LINEAR16';
    //const sampleRateHertz = 16000;
    const languageCode = 'en-US';

    const config = {
        //encoding: encoding,                 // auto detect if load from wav file
        //sampleRateHertz: sampleRateHertz,   // auto detect if load from wav file
        languageCode: languageCode,           // language code is used in wav file
    };
    const audio = {
        content: mFs.readFileSync(wavFile).toString('base64'),
        //content:content,
    };
    //mUtil.log(audio.content);

    const request = {
        config: config,
        audio: audio,
    };

    // Create output text file if it does not exist
    mFs.exists(txtFile, function(exists) {
        if (!exists) {
            mFs.closeSync(mFs.openSync(txtFile, 'w'));
        }
    });

    // Detects speech in the audio file
    try {
        const [response] = await client.recognize(request);
        const transcription = response.results
            .map(result => result.alternatives[0].transcript)
            .join('\n');
        const confidence = response.results
            .map(result => result.alternatives[0].confidence)
            .join('\n');

        // Append transcription text to file
        mFs.appendFile(txtFile,
            mUtil.format('%s:%s\nDuration:%d\nConfidence: %s\n',
                mPath.basename(wavFile), transcription ? transcription : 'No data',
                duration,
                confidence),
            function (err) {
                if (err) mUtil.log(err.message);
        });
        mUtil.log('File:%s Transcription: %s', wavFile, transcription);
        mUtil.log('Confidence: %s', confidence);
        
        //mUtil.log('Word-Level-Confidence:');
        //const words = response.results.map(result => result.alternatives[0]);
        //words[0].words.forEach(a => {
        //    mUtil.log(` word: ${a.word}, confidence: ${a.confidence}`);
        //});
    } catch (error) {
        mUtil.log(error.message);
        mFs.appendFile(txtFile,
            mUtil.format('%s:%s\nDuration:%d\n', mPath.basename(wavFile), error.message, duration),
            function (err) {
                if (err) mUtil.log(err.message);
        });
    }
}*/
// Send content(string base64) to Google Speech To Text (GG STT)
async function sendSTT(wavFile, txtFile, duration) {
    mUtil.log("GG STT start");
    if (!mFs.existsSync(wavFile)) {
        mUtil.log("%s does not exist", wavFile);
        return;
    }


    // Create output text file if it does not exist
    mFs.exists(txtFile, function(exists) {
        if (!exists) {
            mFs.closeSync(mFs.openSync(txtFile, 'w'));
        }
    });

    // Detects speech in the audio file
    try {

        ami.init(function (text){
            const transcription = text;
            // Append transcription text to file
            mFs.appendFile(txtFile,
                mUtil.format('%s:%s\nDuration:%d\n',
                    mPath.basename(wavFile), transcription ? transcription : 'No data',
                    duration,
                    ),
                function (err) {
                    if (err) mUtil.log(err.message);
            });
            mUtil.log('File:%s Transcription: %s', wavFile, transcription);
        })
        ami.http_request_send_file(wavFile);
        //mUtil.log('Word-Level-Confidence:');
        //const words = response.results.map(result => result.alternatives[0]);
        //words[0].words.forEach(a => {
        //    mUtil.log(` word: ${a.word}, confidence: ${a.confidence}`);
        //});
    } catch (error) {
        mUtil.log(error.message);
        mFs.appendFile(txtFile,
            mUtil.format('%s:%s\nDuration:%d\n', mPath.basename(wavFile), error.message, duration),
            function (err) {
                if (err) mUtil.log(err.message);
        });
    }
}

// @@@@@@@@@@@@@@@@@@ STT Handle @@@@@@@@@@@@@@@@@@

// @@@@@@@@@@@@@@@@@@ RecordingInfos Handle @@@@@@@@@@@@@@@@@@
function GetRecordingDirObject(appType, recordingDirName)
{
    var recordingDirObj = RecordingInfos[appType][recordingDirName];
    return recordingDirObj;
}


// Delete RecordingInfo out of RecordingInfos
function DeleteRecordingInfo(recordingName)
{
    var recordingDirObj;
    var recordingNames = recordingName.split('/');
    if (recordingNames.length < 2) {
        mUtil.log("DeleteRecordingInfo recordingName(%s) is invalid", recordingName);
        return;
    }

    // 1-1 call
    if (recordingNames[0] == AppType.Dial)
    {
        recordingDirObj = RecordingInfos[recordingNames[0]][recordingNames[1]];
        if (recordingDirObj
            && !recordingDirObj[STTFlag]
            && recordingDirObj[STTFuncs].length == 0)
        {
            delete RecordingInfos[recordingNames[0]][recordingNames[1]];
        }
    }
    // Other calls: conference ...
    else
    {
        mUtil.log("DeleteRecordingInfo recordingNames: ", recordingNames);
    }
    
    return recordingDirObj;
}

// Create RecordingInfo then add into RecordingInfos
function AddRecordingInfo(recordingName, recordingFormat, recordingTime)
{
    var recordingDirObj;
    var recordingNames = recordingName.split('/');
    if (recordingNames.length < 2) {
        mUtil.log("AddRecordingInfo recordingName(%s) is invalid", recordingName);
        return;
    }

    // 1-1 call
    if (recordingNames[0] == AppType.Dial)
    {
        recordingDirObj = RecordingInfos[recordingNames[0]][recordingNames[1]];
        if (!recordingDirObj) {
            RecordingInfos[recordingNames[0]][recordingNames[1]] = {
                [STTFlag]: false,
                [STTText]: RecordingTextFilePath(mPath.join(recordingNames[0],recordingNames[1]), recordingNames[1], RecordingSTTExt),
                [STTFuncs]: [],
            };
            recordingDirObj = RecordingInfos[recordingNames[0]][recordingNames[1]];
        }
        recordingDirObj[STTFuncs].push(async function(){
            await sendSTT(RecordingAudioFilePath(recordingName, recordingFormat),
                RecordingTextFilePath(mPath.join(recordingNames[0], recordingNames[1]), recordingNames[1], RecordingSTTExt),
                recordingTime);
        });
        
    }
    // Other calls: conference ...
    else
    {
        mUtil.log("AddRecordingInfo recordingNames: ", recordingNames);
    }
    
    return recordingDirObj;
}

// Create emtpy RecordingInfo then add into RecordingInfos
function CreateRecordingInfo(callerName, calleeName)
{
    // Create RecordingInfos directory object
    if (!RecordingInfos)
    {
        RecordingInfos = {};
    }
    
    // Add new AppType object - Parent directory
    if (!RecordingInfos[AppType.Dial])
    {
        RecordingInfos[AppType.Dial] = {};
    }

    // Do not add recordingDir object when empty channel
    if (!callerName || !calleeName)
    {
        return;
    }

    // {AppType.Dial}/{callerName}_{calleeName}/{fileName}
    var recordingDir = AriDialRecordingDirName(callerName, calleeName);

    // Add new channel info object - Sub directory
    if (!RecordingInfos[AppType.Dial][recordingDir])
    {
        RecordingInfos[AppType.Dial][recordingDir] = {
            [STTFlag]: false,
            [STTText]: RecordingTextFilePath(mPath.join(AppType.Dial, recordingDir), recordingDir, RecordingSTTExt),
            [STTFuncs]: [],
        };
    }
}

// @@@@@@@@@@@@@@@@@@ RecordingInfos Handle @@@@@@@@@@@@@@@@@@


// @@@@@@@@@@@@@@@@@@ Recording Path Handle @@@@@@@@@@@@@@@@@@
// txt file path: {path}/{name}.txt
function RecordingTextFilePath(recordingPath, fileName, fileExt)
{
    return mPath.join(AstSpoolDir, recordingPath, mUtil.format("%s.%s", fileName, fileExt));
}

// wav file path: {path}/{name}.wav
function RecordingAudioFilePath(recordingName, fileExt)
{
    return mPath.join(AstSpoolDir, mUtil.format("%s.%s", recordingName, fileExt));
}

// wav file directory name: {path}/
function AriDialRecordingDirName(callerName, calleeName)
{
    var retStr = callerName.replace("PJSIP/", "") + "_" + calleeName.replace("Local/", "");
    return retStr.replace(";", "_");

}

// Recording Name is recording file path without extension: {path}/{name}
function AriDialRecordingName(callerName, calleeName, fileName) {
    // {AppType.Dial}/{callerName}_{calleeName}/{fileName}
    var recordingDir = AriDialRecordingDirName(callerName, calleeName);
    
    return  mPath.join(AppType.Dial, recordingDir, fileName);
}

function AriDialRecordingNameWithIndex(recordingNameWithoutIndex, index) {
    // {ariDialRecordingName}.{index with leading zero}
    return mUtil.format("%s.%s", recordingNameWithoutIndex, index.toString().padStart(3, '0'));
}

// @@@@@@@@@@@@@@@@@@ Recording Path Handle @@@@@@@@@@@@@@@@@@
