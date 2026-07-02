import QtQuick

Item {
    function numberToKanji(num) {
        if (num === 0) return "零";

        var digits = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"];
        var positions = ["", "十", "百", "千"];
        var largePositions = ["", "万", "億", "兆"];

        var strNum = num.toString();
        var result = "";
        
        var largeIndex = 0;
        
        // Processing in chunks of 4 digits for Japanese system (萬 万 notation)
        for (var i = strNum.length; i > 0; i -= 4) {
            var chunkStart = Math.max(0, i - 4);
            var chunk = strNum.substring(chunkStart, i);
            var chunkStr = "";
            var chunkNum = parseInt(chunk);

            if (chunkNum === 0) {
                largeIndex++;
                continue;
            }

            for (var j = 0; j < chunk.length; j++) {
                var digit = parseInt(chunk[chunk.length - 1 - j]);
                if (digit !== 0) {
                    var pos = positions[j];
                    // Skip writing "一" if it's "一十", "一百" etc.
                    if (digit === 1 && j > 0) {
                        chunkStr = pos + chunkStr;
                    } else {
                        chunkStr = digits[digit] + pos + chunkStr;
                    }
                }
            }

            if (chunkNum > 0) {
                chunkStr += largePositions[largeIndex];
            }

            result = chunkStr + result;
            largeIndex++;
        }
        
        return result;
    }
}

