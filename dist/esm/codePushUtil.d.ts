import { Callback, ErrorCallback, SuccessCallback } from "./callbackUtil";
/**
 * Callback / error / logging utilities.
 */
export declare class CodePushUtil {
    /**
     * Tag used for logging to the console.
     */
    private static TAG;
    /**
     * Performs a copy of all members of fromParameter to toParameter, with the condition that they are unassigned or null in toParameter.
     */
    static copyUnassignedMembers(fromParameter: any, toParameter: any): void;
    /**
     * Given two Cordova style callbacks for success and error, this function returns a node.js
     * style callback where the error is the first parameter and the result the second.
     */
    static getNodeStyleCallbackFor<T>(successCallback: SuccessCallback<T>, errorCallback: {
        (error?: any): void;
    }): Callback<T>;
    /**
     * Gets the message of an error, if any. Otherwise it returns the empty string.
     */
    static getErrorMessage(e: Error | undefined): string;
    /**
     * Logs the error to the console and then forwards it to the provided ErrorCallback, if any.
     */
    static invokeErrorCallback: (error: Error, errorCallback: ErrorCallback) => void;
    /**
     * Logs the error to the console and then throws the error.
     */
    static throwError: (error: Error) => void;
    /**
     * Logs a message using the CodePush tag.
     */
    static logMessage(msg: string): void;
    /**
     * Logs an error message using the CodePush tag.
     */
    static logError(message: String, error?: Error): void;
}
