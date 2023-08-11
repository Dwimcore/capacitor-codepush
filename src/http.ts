import { Callback } from "./callbackUtil";

export const enum Verb {
    GET, HEAD, POST, PUT, DELETE, TRACE, OPTIONS, CONNECT, PATCH
}

export interface Response {
    statusCode: number;
    body?: string;
}

export interface Requester {
    request(verb: Verb, url: string, callback: Callback<Response>): void;
    request(verb: Verb, url: string, requestBody: string, callback: Callback<Response>): void;
}
