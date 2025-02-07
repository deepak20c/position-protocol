// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "hardhat/console.sol";

import "./BitMath.sol";

library LiquidityBitmap {
    uint256 public constant MAX_UINT256 = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    /// @notice Get the position in the mapping
    /// @param pip The bip index for computing the position
    /// @return mapIndex the index in the map
    /// @return bitPos the position in the bitmap
    function position(int128 pip) private pure returns (int128 mapIndex, uint8 bitPos) {
        mapIndex = pip >> 8;
        bitPos = uint8(uint128(pip) & 0xff);
        // % 256
    }

    /// @notice find the next pip has liquidity
    /// @param pip The current pip index
    /// @param lte  Whether to search for the next initialized tick to the left (less than or equal to the starting tick)
    /// @return next The next bit position has liquidity, 0 means no liquidity found
    function findHasLiquidityInOneWords(
        mapping(int128 => uint256) storage self,
        int128 pip,
        bool lte
    ) internal view returns (
        int128 next
    ) {

        if (lte) {
            // main is find the next pip has liquidity
            (int128 wordPos, uint8 bitPos) = position(pip);
            // all the 1s at or to the right of the current bitPos
            uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
            uint256 masked = self[wordPos] & mask;
            //            bool hasLiquidity = (self[wordPos] & 1 << bitPos) != 0;

            // if there are no initialized ticks to the right of or at the current tick, return rightmost in the word
            bool initialized = masked != 0;
            // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
            next = initialized
            ? (pip - int128(bitPos - BitMath.mostSignificantBit(masked)))
            : 0;

            //            if (!hasLiquidity && next != 0) {
            //                next = next + 1;
            //            }

        } else {
            // start from the word of the next tick, since the current tick state doesn't matter
            console.log("find pip", uint256(uint128(pip)));
            (int128 wordPos, uint8 bitPos) = position(pip);
            // all the 1s at or to the left of the bitPos
            uint256 mask = ~((1 << bitPos) - 1);
            uint256 masked = self[wordPos] & mask;
            // if there are no initialized ticks to the left of the current tick, return leftmost in the word
            bool initialized = masked != 0;
            // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
            next = initialized
            ? (pip + int128(BitMath.leastSignificantBit(masked) - bitPos))  // +1
            : 0;

            //            if (!hasLiquidity && next != 0) {
            //                next = next + 1;
            //            }
        }
    }

    function findHasLiquidityPipInCertainWord(
        mapping(int128 => uint256) storage self,
        int128 pip,
        int128 word,
        bool lte
    ) internal view returns (
        int128 next
    ) {
        if(lte){

        }else{

        }
    }

    function findHasLiquidityInMultipleWords(
        mapping(int128 => uint256) storage self,
        int128 pip,
        int128 maxWords,
        bool lte
    ) internal view returns (
        int128 next
    ) {
        int128 startWord = pip >> 8;
        if (lte) {
            // TODO check overflow
            for (int128 i = startWord; i > startWord - maxWords; i--) {
                if (self[i] != 0) {
                    return findHasLiquidityInOneWords(self, i < startWord ? 256 * i + 255 : pip, true);
                }
            }
        } else {
            for (int128 i = startWord; i < startWord + maxWords; i++) {
                // DELETE LOG
                console.log("self i", self[i]);
                if (self[i] != 0) {
                    // avoid load in lte

                    return findHasLiquidityInOneWords(self, i > startWord ? 256 * i : pip, false);
                }
            }
        }
    }

    function hasLiquidity(
        mapping(int128 => uint256) storage self,
        int128 pip
    ) internal view returns (
        bool
    ) {
        (int128 mapIndex, uint8 bitPos) = position(pip);
        return (self[mapIndex] & 1 << bitPos) != 0;
    }

    /// @notice Set all bits in a given range
    /// @dev WARNING THIS FUNCTION IS NOT READY FOR PRODUCTION
    /// only use for generating test data purpose
    /// @param fromPip the pip to set from
    /// @param toPip the pip to set to
    function setBitsInRange(
        mapping(int128 => uint256) storage self,
        int128 fromPip,
        int128 toPip
    ) internal {
        (int128 fromMapIndex, uint8 fromBitPos) = position(fromPip);
        (int128 toMapIndex, uint8 toBitPos) = position(toPip);
        if (toMapIndex == fromMapIndex) {
            // in the same storage
            // Set all the bits in given range of a number
            self[toMapIndex] |= (((1 << (fromBitPos - 1)) - 1) ^ ((1 << toBitPos) - 1));
        } else {
            // need to shift the map index
            // TODO fromMapIndex needs set separately
            self[fromMapIndex] |= (((1 << (fromBitPos - 1)) - 1) ^ ((1 << 255) - 1));
            for (int128 i = fromMapIndex + 1; i < toMapIndex; i++) {
                // pass uint256.MAX to avoid gas for computing
                self[i] = MAX_UINT256;
            }
            // set bits for the last index
            self[toMapIndex] = MAX_UINT256 >> (256 - toBitPos);
        }
    }

    function unsetBitsRange(
        mapping(int128 => uint256) storage self,
        int128 fromPip,
        int128 toPip
    ) internal {
        if (fromPip == toPip) return toggleSingleBit(self, fromPip, false);
        fromPip++;
        toPip++;
        if (toPip < fromPip) {
            int128 n = fromPip;
            fromPip = toPip;
            toPip = n;
        }
        (int128 fromMapIndex, uint8 fromBitPos) = position(fromPip);
        (int128 toMapIndex, uint8 toBitPos) = position(toPip);
        if (toMapIndex == fromMapIndex) {
            //            if(fromBitPos > toBitPos){
            //                uint8 n = fromBitPos;
            //                fromBitPos = toBitPos;
            //                toBitPos = n;
            //            }
            self[toMapIndex] &= toggleBitsFromLToR(MAX_UINT256, fromBitPos, toBitPos);
        } else {
            //TODO check overflow here
            fromBitPos--;
            self[fromMapIndex] &= ~toggleLastMBits(MAX_UINT256, fromBitPos);
            for (int128 i = fromMapIndex + 1; i < toMapIndex; i++) {
                self[i] = 0;
            }
            self[toMapIndex] &= toggleLastMBits(MAX_UINT256, toBitPos);
        }
    }

    function toggleSingleBit(
        mapping(int128 => uint256) storage self,
        int128 pip,
        bool isSet
    ) internal {
        console.log("pip", uint128(pip));
        (int128 mapIndex, uint8 bitPos) = position(pip);
        if (isSet) {
            self[mapIndex] |= 1 << bitPos;
        } else {
            // DELETE LOG
            console.log("toggle");
            console.log("self map index before", self[mapIndex]);
            console.log("bit pos", bitPos);
            self[mapIndex] &= ~(1 << bitPos);
            //            self[mapIndex] ^= 1 << bitPos;
            console.log("self map index", self[mapIndex]);
        }
    }

    function toggleBitsFromLToR(uint256 n, uint8 l, uint8 r) private returns (uint256) {
        console.log("l: ", l, "r: ", r);
        // calculating a number 'num'
        // having 'r' number of bits
        // and bits in the range l
        // to r are the only set bits
        uint256 num = ((1 << r) - 1) ^ ((1 << (l - 1)) - 1);

        // toggle the bits in the
        // range l to r in 'n'
        // and return the number
        return (n ^ num);
    }

    // Function to toggle the last m bits
    function toggleLastMBits(uint256 n, uint8 m) private returns (uint256)
    {

        // Calculating a number 'num' having
        // 'm' bits and all are set
        uint256 num = (1 << m) - 1;

        // Toggle the last m bits and
        // return the number
        return (n ^ num);
    }

}
