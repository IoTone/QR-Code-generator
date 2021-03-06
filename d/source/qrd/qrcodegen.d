/* 
 * QR Code generator library (D)
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
module qrd.qrcodegen;

import std.stdint;
// import std.bitmanip;
import core.stdc.stdint;
import core.stdc.string;
import std.math;

/* 
 * This library creates QR Code symbols, which is a type of two-dimension barcode.
 * Invented by Denso Wave and described in the ISO/IEC 18004 standard.
 * A QR Code structure is an immutable square grid of black and white cells.
 * The library provides functions to create a QR Code from text or binary data.
 * The library covers the QR Code Model 2 specification, supporting all versions (sizes)
 * from 1 to 40, all 4 error correction levels, and 4 character encoding modes.
 * 
 * Ways to create a QR Code object:
 * - High level: Take the payload data and call qrcodegen_encodeText() or qrcodegen_encodeBinary().
 * - Low level: Custom-make the list of segments and call
 *   qrcodegen_encodeSegments() or qrcodegen_encodeSegmentsAdvanced().
 * (Note that all ways require supplying the desired error correction level and various byte buffers.)
 */

public:

     /*---- Macro constants and functions ----*/

    static const auto QRCODEGEN_VERSION_MIN = 1;  // The minimum version number supported in the QR Code Model 2 standard
    static const auto QRCODEGEN_VERSION_MAX = 40;  // The maximum version number supported in the QR Code Model 2 standard

    /*---- Enum and struct types----*/

    /* 
    * The error correction level in a QR Code symbol.
    */
    enum QRCodegenEcc {
        // Must be declared in ascending order of error protection
        // so that an internal qrcodegen function works properly
        LOW = 0 ,  // The QR Code can tolerate about  7% erroneous codewords
        MEDIUM  ,  // The QR Code can tolerate about 15% erroneous codewords
        QUARTILE,  // The QR Code can tolerate about 25% erroneous codewords
        HIGH    ,  // The QR Code can tolerate about 30% erroneous codewords
    };


    /* 
    * The mask pattern used in a QR Code symbol.
    */
    enum QRCodegenMask {
        // A special value to tell the QR Code encoder to
        // automatically select an appropriate mask pattern
        AUTO = -1,
        // The eight actual mask patterns
        MASK_0 = 0,
        MASK_1,
        MASK_2,
        MASK_3,
        MASK_4,
        MASK_5,
        MASK_6,
        MASK_7,
    };


    /* 
    * Describes how a segment's data bits are interpreted.
    */
    enum QRCodegenMode {
        NUMERIC      = 0x1,
        ALPHANUMERIC = 0x2,
        BYTE         = 0x4,
        KANJI        = 0x8,
        ECI          = 0x7,
    };


    /* 
    * A segment of character/binary/control data in a QR Code symbol.
    * The mid-level way to create a segment is to take the payload data
    * and call a factory function such as qrcodegen_makeNumeric().
    * The low-level way to create a segment is to custom-make the bit buffer
    * and initialize a qrcodegen_Segment struct with appropriate values.
    * Even in the most favorable conditions, a QR Code can only hold 7089 characters of data.
    * Any segment longer than this is meaningless for the purpose of generating QR Codes.
    * Moreover, the maximum allowed bit length is 32767 because
    * the largest QR Code (version 40) has 31329 modules.
    */
    struct QRCodegenSegment {
        // The mode indicator of this segment.
        QRCodegenMode mode;
        
        // The length of this segment's unencoded data. Measured in characters for
        // numeric/alphanumeric/kanji mode, bytes for byte mode, and 0 for ECI mode.
        // Always zero or positive. Not the same as the data's bit length.
        int numChars;
        
        // The data bits of this segment, packed in bitwise big endian.
        // Can be null if the bit length is zero.
        uint8_t *data;
        
        // The number of valid data bits used in the buffer. Requires
        // 0 <= bitLength <= 32767, and bitLength <= (capacity of data array) * 8.
        // The character count (numChars) must agree with the mode and the bit buffer length.
        int bitLength;
    };



    class QRCodegen {
        // Calculates the number of bytes needed to store any QR Code up to and including the given version number,
        // as a compile-time constant. For example, 'uint8_t buffer[qrcodegen_BUFFER_LEN_FOR_VERSION(25)];'
        // can store any single QR Code from version 1 to 25 (inclusive). The result fits in an int (or int16).
        // Requires qrcodegen_VERSION_MIN <= n <= qrcodegen_VERSION_MAX.
        
        static int BUFFER_LEN_FOR_VERSION(int n) {
            return ((((n) * 4 + 17) * ((n) * 4 + 17) + 7) / 8 + 1);
        }

        // The worst-case number of bytes needed to store one QR Code, up to and including
        // version 40. This value equals 3918, which is just under 4 kilobytes.
        // Use this more convenient value to avoid calculating tighter memory bounds for buffers.
        static const auto BUFFER_LEN_MAX = BUFFER_LEN_FOR_VERSION(QRCODEGEN_VERSION_MAX);




        /*---- Functions (high level) to generate QR Codes ----*/

        /* 
        * Encodes the given text string to a QR Code, returning true if encoding succeeded.
        * If the data is too long to fit in any version in the given range
        * at the given ECC level, then false is returned.
        * - The input text must be encoded in UTF-8 and contain no NULs.
        * - The variables ecl and mask must correspond to enum constant values.
        * - Requires 1 <= minVersion <= maxVersion <= 40.
        * - The arrays tempBuffer and qrcode must each have a length
        *   of at least qrcodegen_BUFFER_LEN_FOR_VERSION(maxVersion).
        * - After the function returns, tempBuffer contains no useful data.
        * - If successful, the resulting QR Code may use numeric,
        *   alphanumeric, or byte mode to encode the text.
        * - In the most optimistic case, a QR Code at version 40 with low ECC
        *   can hold any UTF-8 string up to 2953 bytes, or any alphanumeric string
        *   up to 4296 characters, or any digit string up to 7089 characters.
        *   These numbers represent the hard upper limit of the QR Code standard.
        * - Please consult the QR Code specification for information on
        *   data capacities per version, ECC level, and text encoding mode.
        */
        static bool encodeText(string text, uint8_t[] tempBuffer, uint8_t[] qrcode,
        QRCodegenEcc ecl, int minVersion, int maxVersion, QRCodegenMask mask, bool boostEcl) {
            size_t textLen = text.length;
            if (textLen == 0)
                return encodeSegmentsAdvanced(null, 0, ecl, minVersion, maxVersion, mask, boostEcl, tempBuffer, qrcode);
            size_t bufLen = cast(size_t) BUFFER_LEN_FOR_VERSION(maxVersion);
            
            QRCodegenSegment[1] seg;
            if (isNumeric(text)) {
                if (calcSegmentBufferSize(QRCodegenMode.NUMERIC, textLen) > bufLen)
                    goto fail;
                seg[0] = makeNumeric(text, tempBuffer);
            } else if (isAlphanumeric(text)) {
                if (calcSegmentBufferSize(QRCodegenMode.ALPHANUMERIC, textLen) > bufLen)
                    goto fail;
                seg[0] = makeAlphanumeric(text, tempBuffer);
            } else {
                if (textLen > bufLen)
                    goto fail;
                for (size_t i = 0; i < textLen; i++)
                    tempBuffer[i] = cast(uint8_t) text[i];
                seg[0].mode = QRCodegenMode.BYTE;
                seg[0].bitLength = calcSegmentBitLength(seg[0].mode, textLen);
                if (seg[0].bitLength == -1)
                    goto fail;
                seg[0].numChars = cast(int)textLen;
                seg[0].data = cast(ubyte*)tempBuffer;
            }
            return encodeSegmentsAdvanced(seg, 1, ecl, minVersion, maxVersion, mask, boostEcl, tempBuffer, qrcode);

            fail:
                qrcode[0] = 0;  // Set size to invalid value for safety
                return false;
        }


        /* 
        * Encodes the given binary data to a QR Code, returning true if encoding succeeded.
        * If the data is too long to fit in any version in the given range
        * at the given ECC level, then false is returned.
        * - The input array range dataAndTemp[0 : dataLen] should normally be
        *   valid UTF-8 text, but is not required by the QR Code standard.
        * - The variables ecl and mask must correspond to enum constant values.
        * - Requires 1 <= minVersion <= maxVersion <= 40.
        * - The arrays dataAndTemp and qrcode must each have a length
        *   of at least qrcodegen_BUFFER_LEN_FOR_VERSION(maxVersion).
        * - After the function returns, the contents of dataAndTemp may have changed,
        *   and does not represent useful data anymore.
        * - If successful, the resulting QR Code will use byte mode to encode the data.
        * - In the most optimistic case, a QR Code at version 40 with low ECC can hold any byte
        *   sequence up to length 2953. This is the hard upper limit of the QR Code standard.
        * - Please consult the QR Code specification for information on
        *   data capacities per version, ECC level, and text encoding mode.
        */
        static bool encodeBinary(uint8_t[] dataAndTemp, size_t dataLen, uint8_t[] qrcode,
            QRCodegenEcc ecl, int minVersion, int maxVersion, QRCodegenMask mask, bool boostEcl) {
            QRCodegenSegment[1] seg;
            seg[0].mode = QRCodegenMode.BYTE;
            seg[0].bitLength = calcSegmentBitLength(seg[0].mode, dataLen);
            if (seg[0].bitLength == -1) {
                qrcode[0] = 0;  // Set size to invalid value for safety
                return false;
            }
            seg[0].numChars = cast(int)dataLen;
            seg[0].data = cast(ubyte*)dataAndTemp;
            return encodeSegmentsAdvanced(seg, 1, ecl, minVersion, maxVersion, mask, boostEcl, dataAndTemp, qrcode);
        }


        /*---- Functions (low level) to generate QR Codes ----*/

        /* 
        * Renders a QR Code representing the given segments at the given error correction level.
        * The smallest possible QR Code version is automatically chosen for the output. Returns true if
        * QR Code creation succeeded, or false if the data is too long to fit in any version. The ECC level
        * of the result may be higher than the ecl argument if it can be done without increasing the version.
        * This function allows the user to create a custom sequence of segments that switches
        * between modes (such as alphanumeric and byte) to encode text in less space.
        * This is a low-level API; the high-level API is qrcodegen_encodeText() and qrcodegen_encodeBinary().
        * To save memory, the segments' data buffers can alias/overlap tempBuffer, and will
        * result in them being clobbered, but the QR Code output will still be correct.
        * But the qrcode array must not overlap tempBuffer or any segment's data buffer.
        */
        static bool encodeSegments(const QRCodegenSegment[] segs, size_t len,
            QRCodegenEcc ecl, uint8_t[] tempBuffer, uint8_t[] qrcode) {
            return encodeSegmentsAdvanced(segs, len, ecl,
		QRCODEGEN_VERSION_MIN, QRCODEGEN_VERSION_MAX, QRCodegenMask.AUTO, true, tempBuffer, qrcode);
        }


        /* 
        * Renders a QR Code representing the given segments with the given encoding parameters.
        * Returns true if QR Code creation succeeded, or false if the data is too long to fit in the range of versions.
        * The smallest possible QR Code version within the given range is automatically
        * chosen for the output. Iff boostEcl is true, then the ECC level of the result
        * may be higher than the ecl argument if it can be done without increasing the
        * version. The mask is either between qrcodegen_Mask_0 to 7 to force that mask, or
        * qrcodegen_Mask_AUTO to automatically choose an appropriate mask (which may be slow).
        * This function allows the user to create a custom sequence of segments that switches
        * between modes (such as alphanumeric and byte) to encode text in less space.
        * This is a low-level API; the high-level API is qrcodegen_encodeText() and qrcodegen_encodeBinary().
        * To save memory, the segments' data buffers can alias/overlap tempBuffer, and will
        * result in them being clobbered, but the QR Code output will still be correct.
        * But the qrcode array must not overlap tempBuffer or any segment's data buffer.
        */
        static bool encodeSegmentsAdvanced(const QRCodegenSegment[] segs, size_t len, QRCodegenEcc ecl,
            int minVersion, int maxVersion, QRCodegenMask mask, bool boostEcl, uint8_t[] tempBuffer, uint8_t[] qrcode) {
            assert(segs != null || len == 0);
            assert(QRCODEGEN_VERSION_MIN <= minVersion && minVersion <= maxVersion && maxVersion <= QRCODEGEN_VERSION_MAX);
            assert(0 <= cast(int)ecl && cast(int)ecl <= 3 && -1 <= cast(int)mask && cast(int)mask <= 7);
            
            // Find the minimal version number to use
            int vers, dataUsedBits;
            for (vers = minVersion; ; vers++) {
                int dataCapacityBits = getNumDataCodewords(vers, ecl) * 8;  // Number of data bits available
                dataUsedBits = getTotalBits(segs, len, vers);
                if (dataUsedBits != -1 && dataUsedBits <= dataCapacityBits)
                    break;  // This version number is found to be suitable
                if (vers >= maxVersion) {  // All versions in the range could not fit the given data
                    qrcode[0] = 0;  // Set size to invalid value for safety
                    return false;
                }
            }
            assert(dataUsedBits != -1);
            
            // Increase the error correction level while the data still fits in the current version number
            for (int i = cast(int)QRCodegenEcc.MEDIUM; i <= cast(int)QRCodegenEcc.HIGH; i++) {  // From low to high
                if (boostEcl && dataUsedBits <= getNumDataCodewords(vers, cast(QRCodegenEcc)i) * 8)
                    ecl = cast(QRCodegenEcc)i;
            }
            
            // Concatenate all segments to create the data bit string
            memset(&qrcode, 0, cast(size_t)BUFFER_LEN_FOR_VERSION(vers) * qrcode[0].sizeof);
            int bitLen = 0;
            for (size_t i = 0; i < len; i++) {
                const QRCodegenSegment *seg = &segs[i];
                // (ubyte val, int numBits, ubyte[] buffer, int* bitLen) is not callable using argument types (uint, int, ubyte[], int*)
                appendBitsToBuffer(cast(uint)seg.mode, 4, qrcode, &bitLen);
                appendBitsToBuffer(cast(uint)seg.numChars, numCharCountBits(seg.mode, vers), qrcode, &bitLen);
                for (int j = 0; j < seg.bitLength; j++) {
                    int bit = (seg.data[j >> 3] >> (7 - (j & 7))) & 1;
                    appendBitsToBuffer(cast(uint)bit, 1, qrcode, &bitLen);
                }
            }
            assert(bitLen == dataUsedBits);
            
            // Add terminator and pad up to a byte if applicable
            int dataCapacityBits = getNumDataCodewords(vers, ecl) * 8;
            assert(bitLen <= dataCapacityBits);
            int terminatorBits = dataCapacityBits - bitLen;
            if (terminatorBits > 4)
                terminatorBits = 4;
            appendBitsToBuffer(0, terminatorBits, qrcode, &bitLen);
            appendBitsToBuffer(0, (8 - bitLen % 8) % 8, qrcode, &bitLen);
            assert(bitLen % 8 == 0);
            
            // Pad with alternating bytes until data capacity is reached
            for (uint8_t padByte = 0xEC; bitLen < dataCapacityBits; padByte ^= 0xEC ^ 0x11)
                appendBitsToBuffer(padByte, 8, qrcode, &bitLen);
            
            // Draw function and data codeword modules
            addEccAndInterleave(qrcode, vers, ecl, tempBuffer);
            initializeFunctionModules(vers, qrcode);
            drawCodewords(tempBuffer, getNumRawDataModules(vers) / 8, qrcode);
            drawWhiteFunctionModules(qrcode, vers);
            initializeFunctionModules(vers, tempBuffer);
            
            // Handle masking
            if (mask == QRCodegenMask.AUTO) {  // Automatically choose best mask
                long minPenalty = long.max;
                for (int i = 0; i < 8; i++) {
                    QRCodegenMask msk = cast(QRCodegenMask)i;
                    applyMask(tempBuffer, qrcode, msk);
                    drawFormatBits(ecl, msk, qrcode);
                    long penalty = getPenaltyScore(qrcode);
                    if (penalty < minPenalty) {
                        mask = msk;
                        minPenalty = penalty;
                    }
                    applyMask(tempBuffer, qrcode, msk);  // Undoes the mask due to XOR
                }
            }
            assert(0 <= cast(int)mask && cast(int)mask <= 7);
            applyMask(tempBuffer, qrcode, mask);
            drawFormatBits(ecl, mask, qrcode);
            return true;
        }


        /* 
        * Tests whether the given string can be encoded as a segment in alphanumeric mode.
        * A string is encodable iff each character is in the following set: 0 to 9, A to Z
        * (uppercase only), space, dollar, percent, asterisk, plus, hyphen, period, slash, colon.
        */
        static bool isAlphanumeric(string text) {
            return false;
        }


        /* 
        * Tests whether the given string can be encoded as a segment in numeric mode.
        * A string is encodable iff each character is in the range 0 to 9.
        */
        static bool isNumeric(string text) {
            return false;
        }


        /* 
        * Returns the number of bytes (uint8_t) needed for the data buffer of a segment
        * containing the given number of characters using the given mode. Notes:
        * - Returns SIZE_MAX on failure, i.e. numChars > INT16_MAX or
        *   the number of needed bits exceeds INT16_MAX (i.e. 32767).
        * - Otherwise, all valid results are in the range [0, ceil(INT16_MAX / 8)], i.e. at most 4096.
        * - It is okay for the user to allocate more bytes for the buffer than needed.
        * - For byte mode, numChars measures the number of bytes, not Unicode code points.
        * - For ECI mode, numChars must be 0, and the worst-case number of bytes is returned.
        *   An actual ECI segment can have shorter data. For non-ECI modes, the result is exact.
        */
        static size_t calcSegmentBufferSize(QRCodegenMode mode, size_t numChars) {
            return 0;
        }


        /* 
        * Returns a segment representing the given binary data encoded in
        * byte mode. All input byte arrays are acceptable. Any text string
        * can be converted to UTF-8 bytes and encoded as a byte mode segment.
        */
        static QRCodegenSegment makeBytes(const uint8_t[] data, size_t len, uint8_t[] buf) {
            QRCodegenSegment seg;

            return seg;
        }


        /* 
        * Returns a segment representing the given string of decimal digits encoded in numeric mode.
        */
        static QRCodegenSegment makeNumeric(string digits, uint8_t[] buf) {
            QRCodegenSegment seg;

            return seg;
        }


        /* 
        * Returns a segment representing the given text string encoded in alphanumeric mode.
        * The characters allowed are: 0 to 9, A to Z (uppercase only), space,
        * dollar, percent, asterisk, plus, hyphen, period, slash, colon.
        */
        static QRCodegenSegment makeAlphanumeric(string text, uint8_t[] buf) {
            QRCodegenSegment seg;

            return seg;
        }


        /* 
        * Returns a segment representing an Extended Channel Interpretation
        * (ECI) designator with the given assignment value.
        */
        static QRCodegenSegment makeEci(long assignVal, uint8_t[] buf) {
            QRCodegenSegment seg;

            return seg;
        }

        // Can only be called immediately after a white run is added, and
        // returns either 0, 1, or 2. A helper function for getPenaltyScore().
        static int finderPenaltyCountPatterns(const int[7] runHistory, int qrsize) {
            int n = runHistory[1];
            assert(n <= qrsize * 3);
            bool core = n > 0 && runHistory[2] == n && runHistory[3] == n * 3 && runHistory[4] == n && runHistory[5] == n;
            // The maximum QR Code size is 177, hence the black run length n <= 177.
            // Arithmetic is promoted to int, so n*4 will not overflow.
            return (core && runHistory[0] >= n * 4 && runHistory[6] >= n ? 1 : 0)
                + (core && runHistory[6] >= n * 4 && runHistory[0] >= n ? 1 : 0);
        }


        // Must be called at the end of a line (row or column) of modules. A helper function for getPenaltyScore().
        static int finderPenaltyTerminateAndCount(bool currentRunColor, int currentRunLength, int[7] runHistory, int qrsize) {
            if (currentRunColor) {  // Terminate black run
                finderPenaltyAddHistory(currentRunLength, runHistory, qrsize);
                currentRunLength = 0;
            }
            currentRunLength += qrsize;  // Add white border to final run
            finderPenaltyAddHistory(currentRunLength, runHistory, qrsize);
            return finderPenaltyCountPatterns(runHistory, qrsize);
        }

        // Pushes the given value to the front and drops the last value. A helper function for getPenaltyScore().
        static void finderPenaltyAddHistory(int currentRunLength, int[7] runHistory, int qrsize) {
            if (runHistory[0] == 0)
                currentRunLength += qrsize;  // Add white border to initial run
            memmove(&runHistory[1], &runHistory[0], 6 * runHistory[0].sizeof);
            runHistory[0] = currentRunLength;
        }
        /*---- Functions to extract raw data from QR Codes ----*/

        /* 
        * Returns the side length of the given QR Code, assuming that encoding succeeded.
        * The result is in the range [21, 177]. Note that the length of the array buffer
        * is related to the side length - every 'uint8_t qrcode[]' must have length at least
        * qrcodegen_BUFFER_LEN_FOR_VERSION(version), which equals ceil(size^2 / 8 + 1).
        */
        static int getSize(const uint8_t[] qrcode) {
            assert(qrcode != null);
            int result = qrcode[0];
            assert((QRCODEGEN_VERSION_MIN * 4 + 17) <= result
                && result <= (QRCODEGEN_VERSION_MAX * 4 + 17));
            return result;
        }


        /* 
        * Returns the color of the module (pixel) at the given coordinates, which is false
        * for white or true for black. The top left corner has the coordinates (x=0, y=0).
        * If the given coordinates are out of bounds, then false (white) is returned.
        */
        static bool getModule(const uint8_t[] qrcode, int x, int y) {
            int qrsize = qrcode[0];
            assert(21 <= qrsize && qrsize <= 177 && 0 <= x && x < qrsize && 0 <= y && y < qrsize);
            int index = y * qrsize + x;
	        return getBit(qrcode[(index >> 3) + 1], index & 7);
        }

        // Sets the module at the given coordinates, which must be in bounds.
        static void setModule(uint8_t[] qrcode, int x, int y, bool isBlack) {
            int qrsize = qrcode[0];
            assert(21 <= qrsize && qrsize <= 177 && 0 <= x && x < qrsize && 0 <= y && y < qrsize);
            int index = y * qrsize + x;
            int bitIndex = index & 7;
            int byteIndex = (index >> 3) + 1;
            if (isBlack)
                qrcode[byteIndex] |= 1 << bitIndex;
            else
                qrcode[byteIndex] &= (1 << bitIndex) ^ 0xFF;
        }

        // Sets the module at the given coordinates, doing nothing if out of bounds.
        static void setModuleBounded(uint8_t[] qrcode, int x, int y, bool isBlack) {
            int qrsize = qrcode[0];
            if (0 <= x && x < qrsize && 0 <= y && y < qrsize)
                setModule(qrcode, x, y, isBlack);
        }


        // Returns true iff the i'th bit of x is set to 1. Requires x >= 0 and 0 <= i <= 14.
        static bool getBit(int x, int i) {
            return ((x >> i) & 1) != 0;
        }



        private:
        /*---- Private tables of constants ----*/

        // The set of all legal characters in alphanumeric mode, where each character
        // value maps to the index in the string. For checking text and encoding segments.
        static const string ALPHANUMERIC_CHARSET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";

        // For generating error correction codes.
        static const int8_t[41][4] ECC_CODEWORDS_PER_BLOCK = [
            // Version: (note that index 0 is for padding, and is set to an illegal value)
            //0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40    Error correction level
            [-1,  7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],  // Low
            [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],  // Medium
            [-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],  // Quartile
            [-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],  // High
        ];

        static const auto QRCODEGEN_REED_SOLOMON_DEGREE_MAX  = 30;  // Based on the table above

        // For generating error correction codes.
        static const int8_t[41][4] NUM_ERROR_CORRECTION_BLOCKS = [
            // Version: (note that index 0 is for padding, and is set to an illegal value)
            //0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40    Error correction level
            [-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4,  4,  4,  4,  4,  6,  6,  6,  6,  7,  8,  8,  9,  9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],  // Low
            [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5,  5,  8,  9,  9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],  // Medium
            [-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8,  8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],  // Quartile
            [-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81],  // High
        ];

        // For automatic mask pattern selection.
        static const int PENALTY_N1 =  3;
        static const int PENALTY_N2 =  3;
        static const int PENALTY_N3 = 40;
        static const int PENALTY_N4 = 10;

        // Returns the number of data bits needed to represent a segment
        // containing the given number of characters using the given mode. Notes:
        // - Returns -1 on failure, i.e. numChars > INT16_MAX or
        //   the number of needed bits exceeds INT16_MAX (i.e. 32767).
        // - Otherwise, all valid results are in the range [0, INT16_MAX].
        // - For byte mode, numChars measures the number of bytes, not Unicode code points.
        // - For ECI mode, numChars must be 0, and the worst-case number of bits is returned.
        //   An actual ECI segment can have shorter data. For non-ECI modes, the result is exact.
        static int calcSegmentBitLength(QRCodegenMode mode, size_t numChars) {
            // All calculations are designed to avoid overflow on all platforms
            if (numChars > cast(uint16_t)core.stdc.stdint.INT16_MAX)
                return -1;
            long result = cast(long)numChars;
            if (mode == QRCodegenMode.NUMERIC)
                result = (result * 10 + 2) / 3;  // ceil(10/3 * n)
            else if (mode == QRCodegenMode.ALPHANUMERIC)
                result = (result * 11 + 1) / 2;  // ceil(11/2 * n)
            else if (mode == QRCodegenMode.BYTE)
                result *= 8;
            else if (mode == QRCodegenMode.KANJI)
                result *= 13;
            else if (mode == QRCodegenMode.ECI && numChars == 0) 
                result = 3 * 8;
            else {  // Invalid argument XXX can't hit the return with the asset in D
                // assert(false);
                return -1;
            }
            assert(result >= 0);
            if (result > core.stdc.stdint.INT16_MAX)
                return -1;
            return cast(int)result;
        }

        // Returns the number of 8-bit codewords that can be used for storing data (not ECC),
        // for the given version number and error correction level. The result is in the range [9, 2956].
        static int getNumDataCodewords(int vers, QRCodegenEcc ecl) {
            int v = vers, e = cast(int)ecl;
            assert(0 <= e && e < 4);
            return getNumRawDataModules(v) / 8
                - ECC_CODEWORDS_PER_BLOCK    [e][v]
                * NUM_ERROR_CORRECTION_BLOCKS[e][v];
        }

        // Calculates the number of bits needed to encode the given segments at the given version.
        // Returns a non-negative number if successful. Otherwise returns -1 if a segment has too
        // many characters to fit its length field, or the total bits exceeds INT16_MAX.
        static int getTotalBits(const QRCodegenSegment[] segs, size_t len, int vers) {
            assert(segs != null || len == 0);
            long result = 0;
            for (size_t i = 0; i < len; i++) {
                int numChars  = segs[i].numChars;
                int bitLength = segs[i].bitLength;
                assert(0 <= numChars  && numChars  <= core.stdc.stdint.INT16_MAX);
                assert(0 <= bitLength && bitLength <= core.stdc.stdint.INT16_MAX);
                int ccbits = numCharCountBits(segs[i].mode, vers);
                assert(0 <= ccbits && ccbits <= 16);
                if (numChars >= (1L << ccbits))
                    return -1;  // The segment's length doesn't fit the field's bit width
                result += 4L + ccbits + bitLength;
                if (result > core.stdc.stdint.INT16_MAX)
                    return -1;  // The sum might overflow an int type
            }
            assert(0 <= result && result <= core.stdc.stdint.INT16_MAX);
            return cast(int)result;
        }

        // Appends the given number of low-order bits of the given value to the given byte-based
        // bit buffer, increasing the bit length. Requires 0 <= numBits <= 16 and val < 2^numBits.
        static void appendBitsToBuffer(uint val, int numBits, uint8_t[] buffer, int *bitLen) {
            assert(0 <= numBits && numBits <= 16 && cast(ulong)val >> numBits == 0);
            for (int i = numBits - 1; i >= 0; i--, (*bitLen)++)
                buffer[*bitLen >> 3] |= ((val >> i) & 1) << (7 - (*bitLen & 7));
        }

        // Returns the bit width of the character count field for a segment in the given mode
        // in a QR Code at the given version number. The result is in the range [0, 16].
        static int numCharCountBits(QRCodegenMode mode, int vers) {
            assert(QRCODEGEN_VERSION_MIN <= vers && vers <= QRCODEGEN_VERSION_MAX);
            int i = (vers + 7) / 17;
            final switch (mode) {
                case QRCodegenMode. NUMERIC     : 
                    static const int[] temp1 = [10, 12, 14];
                    return temp1[i];
                case QRCodegenMode.ALPHANUMERIC:
                    static const int[] temp2 = [9, 11, 13];
                    return temp2[i];
                case QRCodegenMode.BYTE        : 
                    static const int[] temp3 = [8, 16, 16];
                    return temp3[i];
                case QRCodegenMode.KANJI       : 
                    static const int[] temp4 = [8, 10, 12];
                    return temp4[i];
                case QRCodegenMode.ECI         :
                    return 0;
            }
        }

        /*---- Error correction code generation functions ----*/
        // Appends error correction bytes to each block of the given data array, then interleaves
        // bytes from the blocks and stores them in the result array. data[0 : dataLen] contains
        // the input data. data[dataLen : rawCodewords] is used as a temporary work area and will
        // be clobbered by this function. The final answer is stored in result[0 : rawCodewords].
        static void addEccAndInterleave(uint8_t[] data, int vers, QRCodegenEcc ecl, uint8_t[] result) {
            // Calculate parameter numbers
            assert(0 <= cast(int)ecl && cast(int)ecl < 4 && QRCODEGEN_VERSION_MIN <= vers && vers <= QRCODEGEN_VERSION_MAX);
            int numBlocks = NUM_ERROR_CORRECTION_BLOCKS[cast(int)ecl][vers];
            int blockEccLen = ECC_CODEWORDS_PER_BLOCK  [cast(int)ecl][vers];
            int rawCodewords = getNumRawDataModules(vers) / 8;
            int dataLen = getNumDataCodewords(vers, ecl);
            int numShortBlocks = numBlocks - rawCodewords % numBlocks;
            int shortBlockDataLen = rawCodewords / numBlocks - blockEccLen;
            
            // Split data into blocks, calculate ECC, and interleave
            // (not concatenate) the bytes into a single sequence
            uint8_t[QRCODEGEN_REED_SOLOMON_DEGREE_MAX] rsdiv;
            reedSolomonComputeDivisor(blockEccLen, rsdiv);
            uint8_t *dat = cast(uint8_t*) data;
            for (int i = 0; i < numBlocks; i++) {
                int datLen = shortBlockDataLen + (i < numShortBlocks ? 0 : 1);
                uint8_t *ecc = &data[dataLen];  // Temporary storage
                // const(ubyte[]) data, int dataLen, const(ubyte[]) generator, int degree, ubyte[] result)
                // (const(ubyte*), int, ubyte[30], int, ubyte*)
                reedSolomonComputeRemainder(dat, datLen, rsdiv, blockEccLen, ecc);
                for (int j = 0, k = i; j < datLen; j++, k += numBlocks) {  // Copy data
                    if (j == shortBlockDataLen)
                        k -= numShortBlocks;
                    result[k] = dat[j];
                }
                for (int j = 0, k = dataLen + i; j < blockEccLen; j++, k += numBlocks)  // Copy ECC
                    result[k] = ecc[j];
                dat += datLen;
            }
        }

        /*---- Drawing function modules ----*/

        // Clears the given QR Code grid with white modules for the given
        // version's size, then marks every function module as black.
        static void initializeFunctionModules(int vers, uint8_t[] qrcode) {
            // Initialize QR Code
            int qrsize = vers * 4 + 17;
            memset(&qrcode, 0, cast(size_t)
            ((qrsize * qrsize + 7) / 8 + 1) * qrcode[0].sizeof);
            qrcode[0] = cast(uint8_t)qrsize;
            
            // Fill horizontal and vertical timing patterns
            fillRectangle(6, 0, 1, qrsize, qrcode);
            fillRectangle(0, 6, qrsize, 1, qrcode);
            
            // Fill 3 finder patterns (all corners except bottom right) and format bits
            fillRectangle(0, 0, 9, 9, qrcode);
            fillRectangle(qrsize - 8, 0, 8, 9, qrcode);
            fillRectangle(0, qrsize - 8, 9, 8, qrcode);
            
            // Fill numerous alignment patterns
            uint8_t[7] alignPatPos;
            int numAlign = getAlignmentPatternPositions(vers, alignPatPos);
            for (int i = 0; i < numAlign; i++) {
                for (int j = 0; j < numAlign; j++) {
                    // Don't draw on the three finder corners
                    if (!((i == 0 && j == 0) || (i == 0 && j == numAlign - 1) || (i == numAlign - 1 && j == 0)))
                        fillRectangle(alignPatPos[i] - 2, alignPatPos[j] - 2, 5, 5, qrcode);
                }
            }
            
            // Fill version blocks
            if (vers >= 7) {
                fillRectangle(qrsize - 11, 0, 3, 6, qrcode);
                fillRectangle(0, qrsize - 11, 6, 3, qrcode);
            }
        }

        // Calculates and stores an ascending list of positions of alignment patterns
        // for this version number, returning the length of the list (in the range [0,7]).
        // Each position is in the range [0,177), and are used on both the x and y axes.
        // This could be implemented as lookup table of 40 variable-length lists of unsigned bytes.
        static int getAlignmentPatternPositions(int vers, uint8_t[7] result) {
            if (vers == 1)
                return 0;
            int numAlign = vers / 7 + 2;
            int step = (vers == 32) ? 26 :
                (vers*4 + numAlign*2 + 1) / (numAlign*2 - 2) * 2;
            for (int i = numAlign - 1, pos = vers * 4 + 10; i >= 1; i--, pos -= step)
                result[i] = cast(uint8_t)pos;
            result[0] = 6;
            return numAlign;
        }

        // Sets every pixel in the range [left : left + width] * [top : top + height] to black.
        static void fillRectangle(int left, int top, int width, int height, uint8_t[] qrcode) {
            for (int dy = 0; dy < height; dy++) {
                for (int dx = 0; dx < width; dx++)
                    setModule(qrcode, left + dx, top + dy, true);
            }
        }

        /*---- Drawing data modules and masking ----*/

        // Draws the raw codewords (including data and ECC) onto the given QR Code. This requires the initial state of
        // the QR Code to be black at function modules and white at codeword modules (including unused remainder bits).
        static void drawCodewords(const uint8_t[] data, int dataLen, uint8_t[] qrcode) {
            int qrsize = getSize(qrcode);
            int i = 0;  // Bit index into the data
            // Do the funny zigzag scan
            for (int right = qrsize - 1; right >= 1; right -= 2) {  // Index of right column in each column pair
                if (right == 6)
                    right = 5;
                for (int vert = 0; vert < qrsize; vert++) {  // Vertical counter
                    for (int j = 0; j < 2; j++) {
                        int x = right - j;  // Actual x coordinate
                        bool upward = ((right + 1) & 2) == 0;
                        int y = upward ? qrsize - 1 - vert : vert;  // Actual y coordinate
                        if (!getModule(qrcode, x, y) && i < dataLen * 8) {
                            bool black = getBit(data[i >> 3], 7 - (i & 7));
                            setModule(qrcode, x, y, black);
                            i++;
                        }
                        // If this QR Code has any remainder bits (0 to 7), they were assigned as
                        // 0/false/white by the constructor and are left unchanged by this method
                    }
                }
            }
            assert(i == dataLen * 8);
        }

        // Returns the number of data bits that can be stored in a QR Code of the given version number, after
        // all function modules are excluded. This includes remainder bits, so it might not be a multiple of 8.
        // The result is in the range [208, 29648]. This could be implemented as a 40-entry lookup table.
        static int getNumRawDataModules(int ver) {
            assert(QRCODEGEN_VERSION_MIN <= ver && ver <= QRCODEGEN_VERSION_MAX);
            int result = (16 * ver + 128) * ver + 64;
            if (ver >= 2) {
                int numAlign = ver / 7 + 2;
                result -= (25 * numAlign - 10) * numAlign - 55;
                if (ver >= 7)
                    result -= 36;
            }
            assert(208 <= result && result <= 29648);
            return result;
        }

        // Draws white function modules and possibly some black modules onto the given QR Code, without changing
        // non-function modules. This does not draw the format bits. This requires all function modules to be previously
        // marked black (namely by initializeFunctionModules()), because this may skip redrawing black function modules.
        static void drawWhiteFunctionModules(uint8_t[] qrcode, int vers) {
            // Draw horizontal and vertical timing patterns
            int qrsize = getSize(qrcode);
            for (int i = 7; i < qrsize - 7; i += 2) {
                setModule(qrcode, 6, i, false);
                setModule(qrcode, i, 6, false);
            }
            
            // Draw 3 finder patterns (all corners except bottom right; overwrites some timing modules)
            for (int dy = -4; dy <= 4; dy++) {
                for (int dx = -4; dx <= 4; dx++) {
                    int dist = abs(dx);
                    if (abs(dy) > dist)
                        dist = abs(dy);
                    if (dist == 2 || dist == 4) {
                        setModuleBounded(qrcode, 3 + dx, 3 + dy, false);
                        setModuleBounded(qrcode, qrsize - 4 + dx, 3 + dy, false);
                        setModuleBounded(qrcode, 3 + dx, qrsize - 4 + dy, false);
                    }
                }
            }
            
            // Draw numerous alignment patterns
            uint8_t[7] alignPatPos;
            int numAlign = getAlignmentPatternPositions(vers, alignPatPos);
            for (int i = 0; i < numAlign; i++) {
                for (int j = 0; j < numAlign; j++) {
                    if ((i == 0 && j == 0) || (i == 0 && j == numAlign - 1) || (i == numAlign - 1 && j == 0))
                        continue;  // Don't draw on the three finder corners
                    for (int dy = -1; dy <= 1; dy++) {
                        for (int dx = -1; dx <= 1; dx++)
                            setModule(qrcode, alignPatPos[i] + dx, alignPatPos[j] + dy, dx == 0 && dy == 0);
                    }
                }
            }
            
            // Draw version blocks
            if (vers >= 7) {
                // Calculate error correction code and pack bits
                int rem = vers;  // version is uint6, in the range [7, 40]
                for (int i = 0; i < 12; i++)
                    rem = (rem << 1) ^ ((rem >> 11) * 0x1F25);
                long bits = cast(long)vers << 12 | rem;  // uint18
                assert(bits >> 18 == 0);
                
                // Draw two copies
                for (int i = 0; i < 6; i++) {
                    for (int j = 0; j < 3; j++) {
                        int k = qrsize - 11 + j;
                        setModule(qrcode, k, i, (bits & 1) != 0);
                        setModule(qrcode, i, k, (bits & 1) != 0);
                        bits >>= 1;
                    }
                }
            }
        }

        // XORs the codeword modules in this QR Code with the given mask pattern.
        // The function modules must be marked and the codeword bits must be drawn
        // before masking. Due to the arithmetic of XOR, calling applyMask() with
        // the same mask value a second time will undo the mask. A final well-formed
        // QR Code needs exactly one (not zero, two, etc.) mask applied.
        static void applyMask(const uint8_t[] functionModules, uint8_t[] qrcode, QRCodegenMask mask) {
            assert(0 <= cast(int)mask && cast(int)mask <= 7);  // Disallows qrcodegen_Mask_AUTO
            int qrsize = getSize(qrcode);
            for (int y = 0; y < qrsize; y++) {
                for (int x = 0; x < qrsize; x++) {
                    if (getModule(functionModules, x, y))
                        continue;
                    bool invert;
                    switch (cast(int)mask) {
                        case 0:  invert = (x + y) % 2 == 0;                    break;
                        case 1:  invert = y % 2 == 0;                          break;
                        case 2:  invert = x % 3 == 0;                          break;
                        case 3:  invert = (x + y) % 3 == 0;                    break;
                        case 4:  invert = (x / 3 + y / 2) % 2 == 0;            break;
                        case 5:  invert = x * y % 2 + x * y % 3 == 0;          break;
                        case 6:  invert = (x * y % 2 + x * y % 3) % 2 == 0;    break;
                        case 7:  invert = ((x + y) % 2 + x * y % 3) % 2 == 0;  break;
                        default: return;
                    }
                    bool val = getModule(qrcode, x, y);
                    setModule(qrcode, x, y, val ^ invert);
                }
            }
        }

        // Draws two copies of the format bits (with its own error correction code) based
        // on the given mask and error correction level. This always draws all modules of
        // the format bits, unlike drawWhiteFunctionModules() which might skip black modules.
        static void drawFormatBits(QRCodegenEcc ecl, QRCodegenMask mask, uint8_t[] qrcode) {
            // Calculate error correction code and pack bits
            assert(0 <= cast(int)mask && cast(int)mask <= 7);
            static const int[] table = [1, 0, 3, 2];
            int data = table[cast(int)ecl] << 3 | cast(int)mask;  // errCorrLvl is uint2, mask is uint3
            int rem = data;
            for (int i = 0; i < 10; i++)
                rem = (rem << 1) ^ ((rem >> 9) * 0x537);
            int bits = (data << 10 | rem) ^ 0x5412;  // uint15
            assert(bits >> 15 == 0);
            
            // Draw first copy
            for (int i = 0; i <= 5; i++)
                setModule(qrcode, 8, i, getBit(bits, i));
            setModule(qrcode, 8, 7, getBit(bits, 6));
            setModule(qrcode, 8, 8, getBit(bits, 7));
            setModule(qrcode, 7, 8, getBit(bits, 8));
            for (int i = 9; i < 15; i++)
                setModule(qrcode, 14 - i, 8, getBit(bits, i));
            
            // Draw second copy
            int qrsize = getSize(qrcode);
            for (int i = 0; i < 8; i++)
                setModule(qrcode, qrsize - 1 - i, 8, getBit(bits, i));
            for (int i = 8; i < 15; i++)
                setModule(qrcode, 8, qrsize - 15 + i, getBit(bits, i));
            setModule(qrcode, 8, qrsize - 8, true);  // Always black
        }

        // Calculates and returns the penalty score based on state of the given QR Code's current modules.
        // This is used by the automatic mask choice algorithm to find the mask pattern that yields the lowest score.
        static long getPenaltyScore(const uint8_t[] qrcode) {
            int qrsize = getSize(qrcode);
            long result = 0;
            
            // Adjacent modules in row having same color, and finder-like patterns
            for (int y = 0; y < qrsize; y++) {
                bool runColor = false;
                int runX = 0;
                int[7] runHistory;
                for (int x = 0; x < qrsize; x++) {
                    if (getModule(qrcode, x, y) == runColor) {
                        runX++;
                        if (runX == 5)
                            result += PENALTY_N1;
                        else if (runX > 5)
                            result++;
                    } else {
                        finderPenaltyAddHistory(runX, runHistory, qrsize);
                        if (!runColor)
                            result += finderPenaltyCountPatterns(runHistory, qrsize) * PENALTY_N3;
                        runColor = getModule(qrcode, x, y);
                        runX = 1;
                    }
                }
                result += finderPenaltyTerminateAndCount(runColor, runX, runHistory, qrsize) * PENALTY_N3;
            }
            // Adjacent modules in column having same color, and finder-like patterns
            for (int x = 0; x < qrsize; x++) {
                bool runColor = false;
                int runY = 0;
                int[7] runHistory;
                for (int y = 0; y < qrsize; y++) {
                    if (getModule(qrcode, x, y) == runColor) {
                        runY++;
                        if (runY == 5)
                            result += PENALTY_N1;
                        else if (runY > 5)
                            result++;
                    } else {
                        finderPenaltyAddHistory(runY, runHistory, qrsize);
                        if (!runColor)
                            result += finderPenaltyCountPatterns(runHistory, qrsize) * PENALTY_N3;
                        runColor = getModule(qrcode, x, y);
                        runY = 1;
                    }
                }
                result += finderPenaltyTerminateAndCount(runColor, runY, runHistory, qrsize) * PENALTY_N3;
            }
            
            // 2*2 blocks of modules having same color
            for (int y = 0; y < qrsize - 1; y++) {
                for (int x = 0; x < qrsize - 1; x++) {
                    bool  color = getModule(qrcode, x, y);
                    if (  color == getModule(qrcode, x + 1, y) &&
                        color == getModule(qrcode, x, y + 1) &&
                        color == getModule(qrcode, x + 1, y + 1))
                        result += PENALTY_N2;
                }
            }
            
            // Balance of black and white modules
            int black = 0;
            for (int y = 0; y < qrsize; y++) {
                for (int x = 0; x < qrsize; x++) {
                    if (getModule(qrcode, x, y))
                        black++;
                }
            }
            int total = qrsize * qrsize;  // Note that size is odd, so black/total != 1/2
            // Compute the smallest integer k >= 0 such that (45-5k)% <= black/total <= (55+5k)%
            int k = cast(int)((abs(black * 20L - total * 10L) + total - 1) / total) - 1;
            result += k * PENALTY_N4;
            return result;
        }

        /*---- Reed-Solomon ECC generator functions ----*/

        // Computes a Reed-Solomon ECC generator polynomial for the given degree, storing in result[0 : degree].
        // This could be implemented as a lookup table over all possible parameter values, instead of as an algorithm.
        static void reedSolomonComputeDivisor(int degree, uint8_t[] result) {
            assert(1 <= degree && degree <= QRCODEGEN_REED_SOLOMON_DEGREE_MAX);
            // Polynomial coefficients are stored from highest to lowest power, excluding the leading term which is always 1.
            // For example the polynomial x^3 + 255x^2 + 8x + 93 is stored as the uint8 array {255, 8, 93}.
            memset(&result, 0, cast(size_t)degree * result[0].sizeof);
            result[degree - 1] = 1;  // Start off with the monomial x^0
            
            // Compute the product polynomial (x - r^0) * (x - r^1) * (x - r^2) * ... * (x - r^{degree-1}),
            // drop the highest monomial term which is always 1x^degree.
            // Note that r = 0x02, which is a generator element of this field GF(2^8/0x11D).
            uint8_t root = 1;
            for (int i = 0; i < degree; i++) {
                // Multiply the current product by (x - r^i)
                for (int j = 0; j < degree; j++) {
                    result[j] = reedSolomonMultiply(result[j], root);
                    if (j + 1 < degree)
                        result[j] ^= result[j + 1];
                }
                root = reedSolomonMultiply(root, 0x02);
            }
        }

        // Computes the Reed-Solomon error correction codeword for the given data and divisor polynomials.
        // The remainder when data[0 : dataLen] is divided by divisor[0 : degree] is stored in result[0 : degree].
        // All polynomials are in big endian, and the generator has an implicit leading 1 term.
        static void reedSolomonComputeRemainder(const uint8_t* data, int dataLen,
                const uint8_t[] generator, int degree, uint8_t* result) {
            assert(1 <= degree && degree <= QRCODEGEN_REED_SOLOMON_DEGREE_MAX);
            memset(result, 0, cast(size_t)degree * result[0].sizeof);
            for (int i = 0; i < dataLen; i++) {  // Polynomial division
                uint8_t factor = data[i] ^ result[0];
                memmove(&result[0], &result[1], cast(size_t)(degree - 1) * result[0].sizeof);
                result[degree - 1] = 0;
                for (int j = 0; j < degree; j++)
                    result[j] ^= reedSolomonMultiply(generator[j], factor);
            }
        }

        // Returns the product of the two given field elements modulo GF(2^8/0x11D).
        // All inputs are valid. This could be implemented as a 256*256 lookup table.
        static uint8_t reedSolomonMultiply(uint8_t x, uint8_t y) {
            // Russian peasant multiplication
            uint8_t z = 0;
            for (int i = 7; i >= 0; i--) {
                z = cast(uint8_t)((z << 1) ^ ((z >> 7) * 0x11D));
                z ^= ((y >> i) & 1) * x;
            }
            return z;
        }
}
