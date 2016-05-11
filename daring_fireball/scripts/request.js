"use strict";
var page = require('webpage').create(),
    system = require('system'),
    t, address;

if (system.args.length === 1) {
    console.log('Usage: request.js <some URL>');
    phantom.exit(1);
} else {
    address = system.args[1];
    page.open(address);

    page.onResourceReceived = function(response) {
      // check if the resource is done downloading
      if (response.stage !== "end") return;
      // apply resource filter if needed:
      if (response.headers.filter(function(header) {
          if (header.name == 'Content-Type' && header.value.indexOf('text/html') == 0) {
              return true;
          }
          return false;
      }).length > 0) {
         system.stdout.writeLine(JSON.stringify(response, undefined, 4));
         phantom.exit();
      }
    };
}
