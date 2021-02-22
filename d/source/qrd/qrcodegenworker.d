/* 
 * QR Code generator test worker (D)
 * 
 * Copyright (c) Project Nayuki. (MIT License)
 * https://www.nayuki.io/page/qr-code-generator-library
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 * - The above copyright notice and this permission notice shall be included in
 *   all copies or substantial portions of the Software.
 * - The Software is provided "as is", without warranty of any kind, express or
 *   implied, including but not limited to the warranties of merchantability,
 *   fitness for a particular purpose and noninfringement. In no event shall the
 *   authors or copyright holders be liable for any claim, damages or other
 *   liability, whether in an action of contract, tort or otherwise, arising from,
 *   out of or in connection with the Software or the use or other dealings in the
 *   Software.
 */
module qrd.qrcodegenworker;

import std.stdio;
import qrd.qrcodegen;
import std.stdint;
import core.stdc.stdio;
import core.stdc.stdlib;

int main() {
	while (true) {
		
		// Read data length or exit
		size_t length;
		{
			int temp;
			if (scanf("%d", &temp) != 1)
				return -1;
			if (temp == -1)
				break;
			length = cast(size_t)temp;
		}
		
		// Read data bytes
		bool isAscii = true;
		uint8_t *data = cast(uint8_t*) malloc(length * uint8_t.sizeof);
		if (data == null) {
			perror("malloc");
			return EXIT_FAILURE;
		}
		for (size_t i = 0; i < length; i++) {
			int b;
			if (scanf("%d", &b) != 1)
				return EXIT_FAILURE;
			data[i] = cast(uint8_t)b;
			isAscii &= 0 < b && b < 128;
		}
		
		// Read encoding parameters
		int errCorLvl, minVersion, maxVersion, mask, boostEcl;
		if (scanf("%d %d %d %d %d", &errCorLvl, &minVersion, &maxVersion, &mask, &boostEcl) != 5)
			return -1;
		
		// Allocate memory for QR Code
		size_t bufferLen = cast(size_t) QRCodegen.BUFFER_LEN_FOR_VERSION(maxVersion);
		uint8_t *qrcode     = cast(uint8_t*) malloc(bufferLen * uint8_t.sizeof);
		uint8_t *tempBuffer = cast(uint8_t*) malloc(bufferLen * uint8_t.sizeof);
		if (qrcode == null || tempBuffer == null) {
			perror("malloc");
			return -1;
		}
		
		// Try to make QR Code symbol
  
		bool ok;
		if (isAscii) {
			char *text = cast(char*) malloc((length + 1) * char.sizeof);
			if (text == null) {
				perror("malloc");
				return -1;
			}
			for (size_t i = 0; i < length; i++)
				text[i] = cast(char)data[i];
			text[length] = '\0';
			ok = QRCodegen.encodeText(text, tempBuffer, qrcode, cast(QRCodegenEcc)errCorLvl,
				minVersion, maxVersion, cast(QRCodegenMask)mask, boostEcl == 1);
			free(text);
		} else if (length <= bufferLen) {
			memcpy(tempBuffer, data, length * sizeof(data[0]));
			ok = qrcodegen_encodeBinary(tempBuffer, length, qrcode, cast(QRCodegenEcc)errCorLvl,
				minVersion, maxVersion, cast(QRCodegenMask)mask, boostEcl == 1);
		} else
			ok = false;
		free(data);
		free(tempBuffer);
		
		if (ok) {
			// Print grid of modules
			int size = qrcodegen_getSize(qrcode);
			printf("%d\n", (size - 17) / 4);
			for (int y = 0; y < size; y++) {
				for (int x = 0; x < size; x++)
					printf("%d\n", QRCodegen.getModule(qrcode, x, y) ? 1 : 0);
			}
		} else
			printf("-1\n");
		// free(qrcode);
		dout.fflush(stdout);
	}
	return 0;
}
